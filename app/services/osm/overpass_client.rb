require "net/http"

module Osm
  # Minimal client for the Overpass API (https://wiki.openstreetmap.org/wiki/Overpass_API).
  # Public instances are often busy, so overloaded responses and timeouts are
  # retried with exponential backoff, moving to the next instance each time.
  class OverpassClient
    class Error < StandardError; end
    class Retryable < Error; end

    # Public instances listed on the OSM wiki; OVERPASS_URLS (comma-separated)
    # or OVERPASS_URL replaces them.
    DEFAULT_URLS = %w[
      https://overpass-api.de/api/interpreter
      https://overpass.private.coffee/api/interpreter
      https://overpass.kumi.systems/api/interpreter
    ].freeze
    RETRYABLE_STATUSES = [ 429, 502, 503, 504 ].freeze
    USER_AGENT = "stepsfrom/1.0 (+https://stepsfrom.com; waterfront verification)".freeze

    def self.configured_urls
      urls = ENV.fetch("OVERPASS_URLS", ENV.fetch("OVERPASS_URL", "")).split(",").map(&:strip).compact_blank
      urls.presence || DEFAULT_URLS
    end

    def initialize(urls: self.class.configured_urls, timeout: 300, attempts: 5, backoff: 15, sleeper: ->(seconds) { sleep(seconds) })
      @uris = Array(urls).map { |url| URI(url) }
      @timeout = timeout
      @attempts = attempts
      @backoff = backoff
      @sleeper = sleeper
    end

    # Runs an Overpass QL query and returns its elements as Osm::Element.
    def query(ql)
      attempt = 0
      begin
        perform(@uris[attempt % @uris.size], ql)
      rescue Retryable => e
        attempt += 1
        raise Error, "#{e.message} (gave up after #{attempt} attempts)" if attempt >= @attempts

        wait = @backoff * (2**(attempt - 1))
        Rails.logger.warn("#{e.message}; retrying in #{wait}s")
        @sleeper.call(wait)
        retry
      end
    end

    private

    def perform(uri, ql)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: 15, read_timeout: @timeout) do |http|
        request = Net::HTTP::Post.new(uri)
        request["User-Agent"] = USER_AGENT
        request.set_form_data(data: ql)
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        message = "#{uri.host} returned HTTP #{response.code}: #{response.body.to_s[0, 200]}"
        raise(RETRYABLE_STATUSES.include?(response.code.to_i) ? Retryable : Error, message)
      end

      json = JSON.parse(response.body)
      # A query that runs out of time or memory still answers 200, with the
      # elements found so far; using them would look like deletions.
      if json["remark"].to_s.include?("runtime error")
        raise Retryable, "#{uri.host} returned partial data: #{json['remark'].to_s[0, 200]}"
      end

      json.fetch("elements").map { |element| Element.from_json(element) }
    rescue JSON::ParserError, KeyError => e
      raise Error, "Unexpected Overpass response from #{uri.host}: #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
      raise Retryable, "Overpass request to #{uri.host} failed: #{e.message}"
    end
  end
end
