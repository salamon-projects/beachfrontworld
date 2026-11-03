module Osm
  module Importers
    # The streets and paths people can walk along, split into edges at every
    # junction (an OSM node shared by two ways) so pgRouting can measure walks
    # on them (see Walks::Measurement). The network is rebuilt from scratch on
    # each import: edges have no identity worth keeping.
    class WalkNetwork < Base
      WALKABLE = %w[footway path steps pedestrian living_street residential service unclassified track
                    corridor cycleway tertiary tertiary_link secondary secondary_link primary primary_link
                    trunk trunk_link].freeze
      # Crossing one of these on foot counts as a busy-road crossing.
      BUSY = %w[primary primary_link secondary secondary_link trunk trunk_link].freeze
      FOOT_ALLOWED = %w[yes designated permissive].freeze

      def call
        ways = client.query(query).select { |element| walkable?(element) }
        return 0 if ways.empty?

        edges, vertices = split(ways)
        WalkEdge.transaction do
          destination.walk_edges.delete_all
          destination.walk_vertices.delete_all
          edges.each_slice(1000) { |batch| WalkEdge.insert_all(batch) }
          vertices.each_slice(1000) { |batch| WalkVertex.insert_all(batch) }
          destination.walk_edges.update_all("length_m = ST_Length(geom)")
        end
        edges.size
      end

      private

      def selectors
        [ %(way["highway"~"^(#{WALKABLE.join('|')})$"]) ]
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

      # Edges between junctions, and the vertices at their ends.
      def split(ways)
        uses = Hash.new(0)
        ways.each do |way|
          way.nodes.each { |node| uses[node] += 1 }
          # A way's ends are vertices even when no other way touches them.
          uses[way.nodes.first] += 1
          uses[way.nodes.last] += 1
        end

        edges = []
        vertices = {}
        ways.each do |way|
          busy = BUSY.include?(way.tags["highway"])
          start = 0
          (1...way.nodes.size).each do |index|
            next unless uses[way.nodes[index]] > 1

            edges << edge_row(way, start, index, busy)
            [ start, index ].each do |at|
              vertex = (vertices[way.nodes[at]] ||= vertex_row(way.nodes[at], way.coords[at]))
              vertex[:busy] ||= busy
            end
            start = index
          end
        end
        [ edges, vertices.values ]
      end

      def edge_row(way, from, to, busy)
        { destination_id: destination.id, osm_way_id: way.id, source: way.nodes[from], target: way.nodes[to],
          highway: way.tags["highway"], steps: way.tags["highway"] == "steps", busy:,
          geom: Geo.line(way.coords[from..to]) }
      end

      def vertex_row(node, (lon, lat))
        { destination_id: destination.id, node_id: node, busy: false, geom: Geo.point(lon:, lat:) }
      end
    end
  end
end
