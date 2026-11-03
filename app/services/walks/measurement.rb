module Walks
  # Measures how far each property of a destination is from each of its
  # landmarks on foot, along the walk network (Osm::Importers::WalkNetwork),
  # and stores the result as PropertyWalk rows.
  #
  # For every landmark, pgRouting grows a shortest-path tree over the network
  # from a virtual root joined to where the landmark meets the network: the
  # junctions within landmark_reach_m of a square, park or street, and the
  # two ends of the way nearest to it, each at the distance still to walk.
  # A property joins the tree at the ends of its nearest way. Along the tree
  # we count flights of steps, and busy-road crossings: junctions on a
  # primary, secondary or trunk road that the walk passes through without
  # following that road.
  class Measurement
    ROOT = Network::ROOT

    def initialize(destination, config: Walks.config)
      @destination = destination
      @config = config
    end

    # Measures the given properties (default: all of the destination's) and
    # replaces their walks. Returns the number of walks stored.
    # progress, when given, is called as progress.(landmarks_done, landmarks_total).
    def call(property_ids: nil, progress: nil)
      started_at = Time.current
      landmarks = @destination.landmarks.order(:id).pluck(:id)
      stored = 0
      with_temp_tables(property_ids) do
        landmarks.each_with_index do |landmark_id, index|
          progress&.call(index, landmarks.size)
          stored += measure(landmark_id, started_at)
        end
      end
      remove_stale(property_ids, started_at)
      stored
    end

    private

    def connection = ActiveRecord::Base.connection

    def max_walk_m = @config.fetch(:max_walk_m)

    def with_temp_tables(property_ids)
      connection.execute("DROP TABLE IF EXISTS walk_snaps, walk_tree")
      connection.execute(snaps_sql(property_ids))
      yield
    ensure
      connection.execute("DROP TABLE IF EXISTS walk_snaps, walk_tree")
    end

    # Where each property joins the network: its nearest way, how far along
    # it, and how far the property is from it.
    def snaps_sql(property_ids)
      ids = Array(property_ids).map { |id| Integer(id) }
      ActiveRecord::Base.sanitize_sql_array([ <<~SQL, destination_id: @destination.id, max_access: @config.fetch(:max_access_m) ])
        CREATE TEMP TABLE walk_snaps AS
        SELECT p.id AS property_id, p.lonlat, e.source, e.target, e.length_m, e.busy AS edge_busy,
               ST_LineLocatePoint(e.geom::geometry, p.lonlat::geometry) AS fraction,
               ST_Distance(e.geom, p.lonlat) AS access_m
        FROM properties p
        CROSS JOIN LATERAL (
          SELECT * FROM walk_edges e WHERE e.destination_id = :destination_id
          ORDER BY e.geom <-> p.lonlat LIMIT 1
        ) e
        WHERE p.destination_id = :destination_id AND p.osm_missing_since IS NULL
          #{"AND p.id IN (#{ids.join(',')})" if property_ids}
          AND ST_Distance(e.geom, p.lonlat) <= :max_access
      SQL
    end

    def measure(landmark_id, started_at)
      starts = Network.start_costs(@destination, landmark_id, reach: @config.fetch(:landmark_reach_m))
      return 0 if starts.empty?

      connection.execute("DROP TABLE IF EXISTS walk_tree")
      connection.execute(tree_sql(landmark_id, starts))
      connection.exec_update(store_sql(landmark_id, started_at))
    end

    # The shortest-path tree from the landmark, with the steps and busy
    # crossings on the way from each junction to the landmark.
    def tree_sql(landmark_id, starts)
      edges_sql = Network.edges_sql(@destination, landmark_id, max_walk_m, starts.map { |node, cost| [ ROOT, node, cost ] })

      ActiveRecord::Base.sanitize_sql_array([ <<~SQL, edges_sql, ROOT, max_walk_m, @destination.id ])
        CREATE TEMP TABLE walk_tree AS
        WITH RECURSIVE dd AS (
          SELECT node, pred, edge, agg_cost FROM pgr_drivingDistance(?, ?::bigint, ?, directed => false)
        ),
        tree(node, edge, agg_cost, crossings, stairs) AS (
          SELECT node, edge, agg_cost, 0, 0 FROM dd WHERE node = #{ROOT}
          UNION ALL
          SELECT child.node, child.edge, child.agg_cost,
                 parent.crossings + CASE WHEN junction.busy AND parent_edge.id IS NOT NULL AND NOT parent_edge.busy
                                              AND child_edge.id IS NOT NULL AND NOT child_edge.busy THEN 1 ELSE 0 END,
                 parent.stairs + CASE WHEN child_edge.steps THEN 1 ELSE 0 END
          FROM dd child
          JOIN tree parent ON child.pred = parent.node AND child.node <> #{ROOT}
          LEFT JOIN walk_edges child_edge ON child_edge.id = child.edge
          LEFT JOIN walk_edges parent_edge ON parent_edge.id = parent.edge
          LEFT JOIN walk_vertices junction ON junction.destination_id = ? AND junction.node_id = parent.node
        )
        SELECT * FROM tree
      SQL
    end

    # Each property's walk through whichever end of its way is closer to the
    # landmark. Never shorter than the straight line.
    def store_sql(landmark_id, started_at)
      ActiveRecord::Base.sanitize_sql_array([ <<~SQL, landmark_id:, destination_id: @destination.id, max: max_walk_m, at: started_at ])
        INSERT INTO property_walks (property_id, landmark_id, walk_m, busy_crossings, stairs, measured_at)
        SELECT s.property_id, :landmark_id,
               ROUND(GREATEST(best.walk_m, ST_Distance(s.lonlat, (SELECT geom FROM landmarks WHERE id = :landmark_id)))),
               best.crossings, best.stairs, :at
        FROM walk_snaps s
        CROSS JOIN LATERAL (
          SELECT s.access_m + ends.along + t.agg_cost AS walk_m, t.stairs,
                 t.crossings + CASE WHEN junction.busy AND NOT s.edge_busy AND next_edge.id IS NOT NULL
                                         AND NOT next_edge.busy THEN 1 ELSE 0 END AS crossings
          FROM (VALUES (s.source, s.fraction * s.length_m), (s.target, (1 - s.fraction) * s.length_m)) ends(node, along)
          JOIN walk_tree t ON t.node = ends.node
          LEFT JOIN walk_edges next_edge ON next_edge.id = t.edge
          LEFT JOIN walk_vertices junction ON junction.destination_id = :destination_id AND junction.node_id = t.node
          ORDER BY walk_m
          LIMIT 1
        ) best
        WHERE best.walk_m <= :max
        ON CONFLICT (property_id, landmark_id) DO UPDATE
        SET walk_m = EXCLUDED.walk_m, busy_crossings = EXCLUDED.busy_crossings, stairs = EXCLUDED.stairs,
            measured_at = EXCLUDED.measured_at
      SQL
    end

    # Walks of the measured properties that this run did not confirm: the
    # landmark is gone, out of reach, or the property left the network.
    def remove_stale(property_ids, started_at)
      scope = PropertyWalk.where(property_id: @destination.properties.select(:id)).where(measured_at: ...started_at)
      scope = scope.where(property_id: property_ids) if property_ids
      scope.delete_all
    end
  end
end
