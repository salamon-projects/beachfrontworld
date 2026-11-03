module Walks
  # The way a measured walk goes, for drawing on the property's map: the
  # shortest path over the walk network from the property to the landmark,
  # as lines of [lat, lon] (more than one when the network has a gap).
  class Route
    def initialize(walk, cache: Rails.cache)
      @walk = walk
      @cache = cache
    end

    # nil when the walk can no longer be traced (the network changed).
    def lines
      @cache.fetch([ "walk-route", @walk.id, @walk.measured_at.to_i ], expires_in: 1.week) { trace }.presence
    end

    private

    def destination = @walk.property.destination

    def trace
      snap = property_snap or return []
      starts = Network.start_costs(destination, @walk.landmark_id)
      return [] if starts.empty?

      virtual = starts.map { |node, cost| [ Network::ROOT, node, cost ] } +
                [ [ Network::PROPERTY, snap["source"], snap["to_source"] ], [ Network::PROPERTY, snap["target"], snap["to_target"] ] ]
      edges_sql = Network.edges_sql(destination, @walk.landmark_id, Walks.config.fetch(:max_walk_m), virtual)
      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, edges_sql, Network::PROPERTY, Network::ROOT ])
        SELECT ST_AsGeoJSON(ST_LineMerge(ST_Collect(e.geom::geometry ORDER BY path.seq)))
        FROM pgr_dijkstra(?, ?::bigint, ?::bigint, directed => false) path
        JOIN walk_edges e ON e.id = path.edge
      SQL
      geojson = ActiveRecord::Base.connection.select_value(sql) or return []
      to_lines(JSON.parse(geojson))
    end

    # Where the property joins the network, and the walk to each end of
    # that way.
    def property_snap
      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, property_id: @walk.property_id, destination_id: destination.id ])
        SELECT e.source, e.target,
               ST_Distance(e.geom, p.lonlat) + ST_LineLocatePoint(e.geom::geometry, p.lonlat::geometry) * e.length_m AS to_source,
               ST_Distance(e.geom, p.lonlat) + (1 - ST_LineLocatePoint(e.geom::geometry, p.lonlat::geometry)) * e.length_m AS to_target
        FROM properties p
        CROSS JOIN LATERAL (
          SELECT * FROM walk_edges e WHERE e.destination_id = :destination_id ORDER BY e.geom <-> p.lonlat LIMIT 1
        ) e
        WHERE p.id = :property_id
      SQL
      ActiveRecord::Base.connection.select_one(sql)
    end

    def to_lines(geometry)
      lines = geometry["type"] == "MultiLineString" ? geometry["coordinates"] : [ geometry["coordinates"] ]
      lines.map { |line| line.map { |lon, lat| [ lat.round(6), lon.round(6) ] } }
    end
  end
end
