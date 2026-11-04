require "net/http"

module Osm
  # Finds OpenStreetMap places by name, in any language, with Nominatim
  # (https://nominatim.org/release-docs/latest/api/Search/). The public
  # instance allows one request a second from an identified client and asks
  # for results to be cached (https://operations.osmfoundation.org/policies/nominatim/);
  # NOMINATIM_URL points to another instance.
  class Nominatim
    DEFAULT_URL = "https://nominatim.openstreetmap.org".freeze
    USER_AGENT = "stepsfrom/1.0 (+https://stepsfrom.com; walks measured to searched places)".freeze
    LIMIT = 5

    Place = Data.define(:osm_type, :osm_id, :category, :type, :names, :display_name, :lat, :lon, :geojson,
                        :importance, :city, :country_code) do
      def self.from_json(json)
        address = json.fetch("address", {})
        new(osm_type: json.fetch("osm_type"), osm_id: Integer(json.fetch("osm_id")),
            category: json["category"] || json["class"], type: json["type"],
            names: json["namedetails"] || {}, display_name: json["display_name"].to_s,
            lat: Float(json.fetch("lat")), lon: Float(json.fetch("lon")), geojson: json["geojson"],
            importance: json["importance"].to_f,
            city: address.values_at("city", "town", "village", "municipality", "county").compact.first,
            country_code: address["country_code"])
      end
    end

    def initialize(url: ENV.fetch("NOMINATIM_URL", DEFAULT_URL), cache: Rails.cache, sleeper: ->(seconds) { sleep(seconds) })
      @uri = URI("#{url.chomp('/')}/search")
      @cache = cache
      @sleeper = sleeper
    end

    # Matching places, the most likely first; nil when Nominatim could not
    # be asked.
    def search(text)
      results = @cache.fetch([ "nominatim", text.downcase ], expires_in: 30.days, skip_nil: true) { request(text) }
      results&.map { |json| Place.from_json(json) }
    rescue KeyError, ArgumentError, TypeError => e
      Rails.logger.warn("Nominatim: unexpected result for #{text.inspect}: #{e.message}")
      nil
    end

    private

    def request(text)
      return unless take_turn

      uri = @uri.dup
      uri.query = URI.encode_www_form(q: text, format: "jsonv2", limit: LIMIT, addressdetails: 1, namedetails: 1,
                                      polygon_geojson: 1, polygon_threshold: 0.0001, "accept-language": "en")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 8) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT))
      end
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("Nominatim: HTTP #{response.code} from #{uri.host}")
        return
      end

      results = JSON.parse(response.body)
      results if results.is_a?(Array)
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      Rails.logger.warn("Nominatim failed: #{e.class}: #{e.message}")
      nil
    end

    # One request a second across all app processes: waits for the next
    # second once, then gives up.
    def take_turn
      2.times do |attempt|
        now = Time.current
        count = @cache.increment([ "nominatim-turn", now.to_i ], 1, expires_in: 10.seconds)
        return true if count.nil? || count <= 1

        @sleeper.call(1 - (now.to_f % 1)) if attempt.zero?
      end
      false
    end
  end
end
