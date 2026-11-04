module Osm
  module Importers
    # Places visitors want to stay near: sights, museums, squares, pedestrian
    # streets, parks, beaches, stations and markets. Sights and monuments are
    # only taken when they have a Wikidata or Wikipedia entry, which keeps out
    # the thousands of small plaques and memorials of a city. The ways of a
    # pedestrian street are joined into one landmark per name.
    class Landmarks < Base
      NOTABLE = %w[attraction historic place_of_worship viewpoint].freeze

      def call
        seen_at = Time.current
        groups = client.query(query).filter_map { |element| candidate(element) }.group_by { |c| c[:key] }
        count = groups.values.count { |candidates| save(candidates, seen_at) }
        @removed = remove_missing(seen_at) if count.positive?
        count
      end

      private

      def model = Landmark

      # Places found for a search stay until OSM drops them from a search.
      def layer_scope = destination.landmarks.source_import

      def selectors
        [ 'nwr["tourism"~"^(attraction|museum|gallery|viewpoint|zoo|theme_park|aquarium)$"]["name"]',
          'nwr["historic"]["name"]["wikidata"]',
          'nwr["amenity"="place_of_worship"]["name"]["wikidata"]',
          'nwr["man_made"~"^(tower|lighthouse)$"]["name"]["wikidata"]',
          'nwr["place"="square"]["name"]',
          'way["highway"="pedestrian"]["name"]',
          'nwr["leisure"~"^(park|garden)$"]["name"]',
          'nwr["natural"="beach"]',
          'nwr["railway"="station"]["name"]',
          'nwr["amenity"="marketplace"]["name"]' ]
      end

      def remove_missing(seen_at)
        layer_scope.where("seen_at IS NULL OR seen_at < ?", seen_at).where(*inside_bbox("geom")).delete_all
      end

      # Landmark attributes for an element, or nil when it is not one.
      def candidate(element)
        tags = element.tags
        kind = kind_for(tags) or return
        return if NOTABLE.include?(kind) && tags["wikidata"].blank? && tags["wikipedia"].blank?

        geom = geometry_for(element, kind) or return
        key = if tags["wikidata"].present? then "wikidata:#{tags['wikidata']}"
        elsif kind == "pedestrian_street" then "street:#{tags['name']}"
        else "osm:#{element.type}/#{element.id}"
        end
        { key:, element:, kind:, geom: }
      end

      def kind_for(tags)
        return "beach" if tags["natural"] == "beach"
        if tags["highway"] == "pedestrian"
          return tags["area"] == "yes" || tags["place"] == "square" ? "square" : "pedestrian_street"
        end
        return "square" if tags["place"] == "square"
        return "station" if tags["railway"] == "station"
        return "market" if tags["amenity"] == "marketplace"
        return "museum" if %w[museum gallery].include?(tags["tourism"])
        return "place_of_worship" if tags["amenity"] == "place_of_worship"
        return "viewpoint" if tags["tourism"] == "viewpoint"
        return "attraction" if %w[attraction zoo theme_park aquarium].include?(tags["tourism"]) || tags["man_made"].present?
        return "historic" if tags["historic"].present?

        "park" if %w[park garden].include?(tags["leisure"])
      end

      def geometry_for(element, kind)
        return element.point if element.node?
        return element.line if kind == "pedestrian_street"

        element.polygon || element.line || element.point
      end

      # Saves one landmark from candidates that are the same place (the ways
      # of a street, or a node and an area with the same Wikidata id).
      def save(candidates, seen_at)
        main = candidates.min_by { |c| [ c[:element].node? ? 1 : 0, c[:element].id ] }
        element = main[:element]
        tags = element.tags
        names = tags.select { |key, value| key.start_with?("name:") && value.present? }.transform_keys { |key| key.delete_prefix("name:") }

        landmark = destination.landmarks.find_or_initialize_by(osm_type: element.type, osm_id: element.id)
        landmark.assign_attributes(
          kind: main[:kind], name: names["en"].presence || tags["name"].presence, local_name: tags["name"].presence,
          names: names.merge(tags.slice("alt_name", "official_name")),
          wikidata: tags["wikidata"].presence, prominence: prominence(tags), seen_at:, source: "import",
          geom: combined_geometry(candidates.map { |c| c[:geom] }, main[:geom])
        )
        landmark.save!
        true
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("Skipping OSM landmark #{element.type}/#{element.id}: #{e.message}")
        false
      end

      # Famous places have Wikipedia articles and names in many languages.
      def prominence(tags)
        languages = tags.keys.count { |key| key.start_with?("name:") }
        [ languages, 60 ].min + (tags["wikidata"].present? ? 20 : 0) + (tags["wikipedia"].present? ? 20 : 0)
      end

      def combined_geometry(geoms, main)
        lines = geoms.select { |geom| geom.geometry_type == RGeo::Feature::LineString }
        return main unless lines.size > 1 && lines.size == geoms.size

        Geo.factory.multi_line_string(lines)
      end
    end
  end
end
