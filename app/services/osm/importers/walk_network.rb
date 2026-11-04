module Osm
  module Importers
    # The streets and paths people can walk along, for pgRouting to measure
    # walks on (see Walks::Measurement). The network is one map shared by
    # every destination and searched place, filled in box by box, so each
    # way is split at every node: an edge then never depends on which other
    # ways were fetched with it, and a junction with a way fetched later
    # simply joins on its node.
    #
    # A big box is fetched in tiles; ways crossing a tile edge come back whole
    # from each tile and are kept once.
    class WalkNetwork < Base
      WALKABLE = %w[footway path steps pedestrian living_street residential service unclassified track
                    corridor cycleway tertiary tertiary_link secondary secondary_link primary primary_link
                    trunk trunk_link].freeze
      # Crossing one of these on foot counts as a busy-road crossing.
      BUSY = %w[primary primary_link secondary secondary_link trunk trunk_link].freeze
      FOOT_ALLOWED = %w[yes designated permissive].freeze
      # Big enough for the area around one searched place in one query.
      TILE_DEGREES = 0.08 # about 9 km north-south
      BATCH = 5000

      # Returns the number of edges stored. An empty answer keeps the network
      # as it was.
      def call
        seen_at = Time.current
        ways = tiles.flat_map { |tile| client.query(query(tile)) }.uniq(&:id).select { |element| walkable?(element) }
        return 0 if ways.empty?

        edges, vertices = split(ways)
        WalkEdge.transaction do
          WalkEdge.where(osm_way_id: ways.map(&:id)).delete_all
          edges.each_slice(BATCH) { |batch| connection.execute(insert_edges_sql(batch, seen_at)) }
          vertices.each_slice(BATCH) { |batch| connection.execute(upsert_vertices_sql(batch, seen_at)) }
          @removed = remove_missing(seen_at)
        end
        edges.size
      end

      private

      def query(tile)
        %([out:json][timeout:300];way["highway"~"^(#{WALKABLE.join('|')})$"](#{tile.join(',')});out geom qt;)
      end

      # [south, west, north, east] tiles covering the box.
      def tiles
        south, west, north, east = bbox
        rows = ((north - south) / TILE_DEGREES).ceil.clamp(1..)
        columns = ((east - west) / TILE_DEGREES).ceil.clamp(1..)
        height = (north - south) / rows
        width = (east - west) / columns
        (0...rows).to_a.product((0...columns).to_a).map do |row, column|
          [ south + row * height, west + column * width, south + (row + 1) * height, west + (column + 1) * width ]
            .map { |degrees| degrees.round(6) }
        end
      end

      def walkable?(element)
        tags = element.tags
        return false unless element.way? && WALKABLE.include?(tags["highway"])
        return false unless element.nodes.size >= 2 && element.nodes.size == element.coords.size
        return FOOT_ALLOWED.include?(tags["foot"]) if tags["foot"].present?
        return false if %w[private no].include?(tags["access"])
        return false if tags["highway"] == "cycleway"
        # Trunk roads are walkable only where a sidewalk is mapped.
        return %w[both left right yes separate].include?(tags["sidewalk"]) if tags["highway"].start_with?("trunk")

        true
      end

      # One edge per pair of consecutive nodes, as
      # [way, from node, to node, highway, busy, from lon/lat, to lon/lat],
      # and the nodes as [node, busy, lon, lat].
      def split(ways)
        edges = []
        vertices = {}
        ways.each do |way|
          highway = way.tags["highway"]
          busy = BUSY.include?(highway)
          way.nodes.each_with_index do |node, index|
            vertex = (vertices[node] ||= [ node, false, *way.coords[index] ])
            vertex[1] ||= busy
            next if index.zero? || way.nodes[index - 1] == node

            edges << [ way.id, way.nodes[index - 1], node, highway, busy, *way.coords[index - 1], *way.coords[index] ]
          end
        end
        [ edges, vertices.values ]
      end

      def connection = ActiveRecord::Base.connection

      # Built in SQL from plain numbers: much faster than geometry objects
      # for the hundred thousand edges of a city centre.
      def insert_edges_sql(edges, seen_at)
        values = edges.map do |way, source, target, highway, busy, lon1, lat1, lon2, lat2|
          "(#{Integer(way)},#{Integer(source)},#{Integer(target)},#{connection.quote(highway)},#{busy}," \
            "#{Float(lon1)},#{Float(lat1)},#{Float(lon2)},#{Float(lat2)})"
        end
        <<~SQL
          INSERT INTO walk_edges (osm_way_id, source, target, highway, steps, busy, seen_at, geom, length_m)
          SELECT way, source, target, highway, highway = 'steps', busy, #{connection.quote(seen_at)}, line, ST_Length(line)
          FROM (VALUES #{values.join(',')}) v(way, source, target, highway, busy, lon1, lat1, lon2, lat2),
          LATERAL (SELECT ST_SetSRID(ST_MakeLine(ST_MakePoint(lon1, lat1), ST_MakePoint(lon2, lat2)), 4326)::geography AS line) l
        SQL
      end

      # A node inside the box was fetched with every way through it, so its
      # busy flag is complete; one outside may sit on a busy road fetched
      # with another box.
      def upsert_vertices_sql(vertices, seen_at)
        south, west, north, east = bbox.map { |degrees| Float(degrees) }
        values = vertices.map { |node, busy, lon, lat| "(#{Integer(node)},#{busy},#{Float(lon)},#{Float(lat)})" }
        <<~SQL
          INSERT INTO walk_vertices (node_id, busy, seen_at, geom)
          SELECT node, busy, #{connection.quote(seen_at)}, ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
          FROM (VALUES #{values.join(',')}) v(node, busy, lon, lat)
          ON CONFLICT (node_id) DO UPDATE SET
            busy = CASE WHEN ST_Intersects(EXCLUDED.geom::geometry, ST_MakeEnvelope(#{west}, #{south}, #{east}, #{north}, 4326))
                        THEN EXCLUDED.busy ELSE walk_vertices.busy OR EXCLUDED.busy END,
            seen_at = EXCLUDED.seen_at, geom = EXCLUDED.geom
        SQL
      end

      # Ways inside the box that OSM no longer returns, and nodes no way uses.
      def remove_missing(seen_at)
        removed = WalkEdge.where("seen_at IS NULL OR seen_at < ?", seen_at).where(*inside_bbox("geom")).delete_all
        WalkVertex.where("seen_at IS NULL OR seen_at < ?", seen_at).where(*inside_bbox("geom")).delete_all
        removed
      end
    end
  end
end
