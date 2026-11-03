module Walks
  # Shared SQL for routing over a destination's walk network with pgRouting.
  # Landmarks and properties join the network through virtual edges from
  # vertices that are not OSM nodes (ROOT for the landmark, PROPERTY for a
  # property), each as long as the walk still to go.
  module Network
    ROOT = 0
    PROPERTY = -1

    module_function

    # { node_id => metres from the landmark } for the junctions where walks
    # to the landmark end: those within reach of a square, park or street,
    # and both ends of the way nearest to the landmark.
    def start_costs(destination, landmark_id, reach: Walks.config.fetch(:landmark_reach_m))
      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, landmark_id:, destination_id: destination.id, reach: ])
        WITH landmark AS (SELECT geom FROM landmarks WHERE id = :landmark_id),
        nearest AS (
          SELECT e.source, e.target, e.length_m, ST_Distance(e.geom, l.geom) AS access_m,
                 ST_LineLocatePoint(e.geom::geometry, ST_ClosestPoint(e.geom::geometry, l.geom::geometry)) AS fraction
          FROM landmark l, LATERAL (
            SELECT * FROM walk_edges e WHERE e.destination_id = :destination_id ORDER BY e.geom <-> l.geom LIMIT 1
          ) e
        )
        SELECT node, MIN(cost) AS cost FROM (
          SELECT v.node_id AS node, ST_Distance(v.geom, l.geom) AS cost
          FROM walk_vertices v, landmark l
          WHERE v.destination_id = :destination_id AND ST_DWithin(v.geom, l.geom, :reach)
          UNION ALL SELECT source, access_m + fraction * length_m FROM nearest
          UNION ALL SELECT target, access_m + (1 - fraction) * length_m FROM nearest
        ) starts
        GROUP BY node
      SQL
      ActiveRecord::Base.connection.select_rows(sql).to_h { |node, cost| [ Integer(node), Float(cost) ] }
    end

    # Edges SQL for pgRouting: the network within radius metres of the
    # landmark, plus virtual edges given as [from, to, metres].
    def edges_sql(destination, landmark_id, radius, virtual_edges)
      virtual = virtual_edges.each_with_index.map do |(from, to, metres), index|
        "SELECT #{-(index + 1)}::bigint, #{Integer(from)}::bigint, #{Integer(to)}::bigint, " \
          "#{Float(metres).round(2)}::float, #{Float(metres).round(2)}::float"
      end
      <<~SQL
        SELECT id, source, target, length_m AS cost, length_m AS reverse_cost FROM walk_edges
        WHERE destination_id = #{Integer(destination.id)}
          AND ST_DWithin(geom, (SELECT geom FROM landmarks WHERE id = #{Integer(landmark_id)}), #{Integer(radius)})
        #{virtual.map { |edge| "UNION ALL #{edge}" }.join("\n")}
      SQL
    end
  end
end
