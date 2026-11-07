module Osm
  module Importers
    # Imports one OSM layer for a destination's bounding box. Features inside
    # the box that the layer's query no longer returns were deleted from OSM
    # (or retagged), so they are removed and measurements use the current map.
    class Base
      # Features this close to the box's edge are never removed: Overpass and
      # PostGIS may disagree on what touches the edge.
      EDGE_MARGIN = 0.001 # degrees, about 100 m

      attr_reader :destination, :client, :removed

      def initialize(destination, client: OverpassClient.new)
        @destination = destination
        @client = client
        @removed = 0
      end

      # Returns the number of imported features; #removed tells how many were
      # deleted. An empty result removes nothing, as it is more likely a broken
      # response than a map without any such features.
      def call
        seen_at = Time.current
        rows = client.query(query).filter_map { |element| row_for(element) }
        import(rows.map { |row| row.merge(seen_at:) })
        @removed = remove_missing(seen_at) if rows.any?
        rows.size
      end

      private

      def query
        "[out:json][timeout:300];(#{selectors.map { |s| "#{s}#{bbox_filter};" }.join});out geom;"
      end

      def bbox_filter
        "(#{destination.bbox.join(',')})"
      end

      def import(rows)
        rows.uniq { |row| row.values_at(*unique_by) }.each_slice(500) do |batch|
          model.upsert_all(batch, unique_by:)
        end
      end

      def unique_by
        %i[osm_type osm_id]
      end

      # The rows this layer owns, when it shares a table with another layer.
      def layer_scope
        model.all
      end

      def remove_missing(seen_at)
        layer_scope.where("seen_at IS NULL OR seen_at < ?", seen_at).where(*inside_bbox("geom")).delete_all
      end

      # SQL condition: the column's geometry lies at least partly inside the
      # bounding box, shrunk by EDGE_MARGIN. Compared in plain lon/lat as
      # Overpass does; the && pre-filter lets the spatial index help.
      def inside_bbox(column)
        south, west, north, east = destination.bbox
        envelope = "ST_MakeEnvelope(:west, :south, :east, :north, 4326)"
        [ "#{column} && #{envelope}::geography AND ST_Intersects(#{column}::geometry, #{envelope})",
          { west: west + EDGE_MARGIN, south: south + EDGE_MARGIN, east: east - EDGE_MARGIN, north: north - EDGE_MARGIN } ]
      end
    end
  end
end
