module Search
  # Finds a place we have not measured yet on OpenStreetMap (Osm::Nominatim)
  # and saves it as a landmark found by search, in the destination around
  # it, ready for its walks to be measured (MeasureLandmarkJob). A sight, a
  # square, a street, a station, a venue or an address all work; a whole
  # town or region does not, as nothing can be measured to it.
  class Locator
    Result = Data.define(:status, :landmark, :place) do
      def self.build(status, landmark: nil, place: nil) = new(status:, landmark:, place:)
    end

    # Nominatim categories and place types too big to stay near.
    AREA_CATEGORIES = %w[boundary landuse].freeze
    AREA_PLACES = %w[continent country state region province district county municipality city borough town
                     village hamlet island archipelago islet].freeze
    # Outlines bigger than this across are measured from their centre.
    MAX_OUTLINE_M = 3000

    def initialize(nominatim: Osm::Nominatim.new)
      @nominatim = nominatim
    end

    # Tries each query (most precise first) until one finds a place.
    # Statuses: :found (with the landmark), :too_big (a town or region,
    # with its name), :not_found and :unavailable.
    def call(queries)
      too_big = nil
      queries.compact_blank.uniq.first(2).each do |query|
        places = @nominatim.search(query)
        return Result.build(:unavailable) if places.nil?

        place = places.find { |candidate| !area?(candidate) }
        return found(place) if place

        too_big ||= places.first
      end
      too_big ? Result.build(:too_big, place: too_big.names["name:en"] || too_big.names["name"]) : Result.build(:not_found)
    end

    private

    def area?(place)
      AREA_CATEGORIES.include?(place.category) || (place.category == "place" && AREA_PLACES.include?(place.type))
    end

    def found(place)
      landmark = Landmark.find_by(osm_type: place.osm_type, osm_id: place.osm_id) || create(place)
      return Result.build(:not_found) unless landmark

      landmark.update_columns(searched_at: Time.current)
      Result.build(:found, landmark:)
    end

    def create(place)
      geom = geometry(place)
      names = place.names.select { |key, value| key.start_with?("name:") && value.present? }.transform_keys { |key| key.delete_prefix("name:") }
      local_name = place.names["name"].presence
      name = names["en"].presence || local_name || place.display_name.split(",").first(2).join(",").squish.presence
      destination = destination_for(place, geom) or return

      Landmark.transaction do
        landmark = destination.landmarks.create!(
          osm_type: place.osm_type, osm_id: place.osm_id, source: "search", kind: kind_for(place, geom),
          name:, local_name:, names: names.merge(place.names.slice("alt_name", "official_name")),
          prominence: (place.importance * 100).round.clamp(0, 100), geom:
        )
        destination.extend_to!(landmark.walk_area) if destination.on_demand?
        landmark
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("Could not save searched place #{place.osm_type}/#{place.osm_id}: #{e.message}")
      Landmark.find_by(osm_type: place.osm_type, osm_id: place.osm_id)
    end

    # The destination around the place, else one of the same town, else a
    # new one for the town, grown to the area around each place searched
    # in it.
    def destination_for(place, geom)
      point = Geo.point(lon: place.lon, lat: place.lat)
      Destination.containing(point).first || town_destination(place, point)
    end

    def town_destination(place, point)
      country_code = place.country_code.to_s.upcase
      return unless country_code.match?(/\A[A-Z]{2}\z/)

      name = place.city.presence || place.names["name:en"] || place.names["name"] or return
      Destination.where(country_code:).where("LOWER(name) = ?", name.downcase).order(:on_demand, :id).first ||
        Destination.create!(name:, country_code:, on_demand: true, published: true, zoom: 14, position: 1000,
                            south: point.y - 0.001, west: point.x - 0.001, north: point.y + 0.001, east: point.x + 0.001)
    end

    # The outline of a street, square or building when Nominatim gives one
    # of a walkable size, else the point.
    def geometry(place)
      point = Geo.point(lon: place.lon, lat: place.lat)
      coordinates = place.geojson&.dig("coordinates")
      shape = case place.geojson&.dig("type")
      when "LineString" then [ coordinates ] if coordinates.size >= 2
      when "Polygon" then [ coordinates.first ] if coordinates.first.size >= 4
      when "MultiPolygon" then coordinates.map(&:first).select { |ring| ring.size >= 4 }.presence
      end
      return point unless shape && small?(shape.flatten(1))

      case place.geojson["type"]
      when "LineString" then Geo.line(shape.first)
      when "Polygon" then Geo.polygon(shape.first)
      else Geo.factory.multi_polygon(shape.map { |ring| Geo.polygon(ring) })
      end
    end

    def small?(coords)
      lons, lats = coords.transpose
      height = (lats.max - lats.min) * Landmark::METRES_PER_DEGREE
      width = (lons.max - lons.min) * Landmark::METRES_PER_DEGREE * Math.cos(lats.min * Math::PI / 180)
      Math.hypot(width, height) <= MAX_OUTLINE_M
    end

    def kind_for(place, geom)
      case [ place.category, place.type ]
      in [ "tourism", "museum" | "gallery" ] then "museum"
      in [ "tourism", "viewpoint" ] then "viewpoint"
      in [ "tourism", "attraction" | "zoo" | "theme_park" | "aquarium" ] | [ "man_made", "tower" | "lighthouse" ] then "attraction"
      in [ "historic", _ ] then "historic"
      in [ "amenity", "place_of_worship" ] then "place_of_worship"
      in [ "amenity", "marketplace" ] then "market"
      in [ "place", "square" ] then "square"
      in [ "highway", "pedestrian" ] then geom.geometry_type == RGeo::Feature::Polygon ? "square" : "pedestrian_street"
      in [ "leisure", "park" | "garden" ] then "park"
      in [ "natural", "beach" ] then "beach"
      in [ "railway" | "public_transport", "station" ] then "station"
      else "place"
      end
    end
  end
end
