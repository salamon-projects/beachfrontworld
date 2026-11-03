require "net/http"

module Search
  # Turns what a visitor typed ("eiffel torony", "quiet place near the beach
  # in Makarska") into a structured query, using a language model behind an
  # OpenAI-compatible chat completions API (Tensorix by default; any other
  # through LLM_BASE_URL and LLM_MODEL). Only the typed text is sent.
  #
  # Returns nil when no model is configured or the call fails; the search
  # then falls back to matching landmark names directly (Search::Resolver).
  class Interpreter
    DEFAULT_BASE_URL = "https://api.tensorix.ai/v1".freeze
    DEFAULT_MODEL = "deepseek/deepseek-chat-v3.1".freeze
    MAX_INPUT = 200

    Result = Data.define(:place, :anchors, :kinds, :max_minutes, :property_kinds) do
      def anchor_names
        anchors.flat_map { |anchor| [ anchor[:name], anchor[:local_name] ] }.compact_blank.uniq
      end
    end

    def self.configured?
      ENV["LLM_API_KEY"].present?
    end

    def initialize(api_key: ENV["LLM_API_KEY"], base_url: ENV.fetch("LLM_BASE_URL", DEFAULT_BASE_URL),
                   model: ENV.fetch("LLM_MODEL", DEFAULT_MODEL), cache: Rails.cache)
      @api_key = api_key
      @uri = URI("#{base_url.chomp('/')}/chat/completions")
      @model = model
      @cache = cache
    end

    def call(text)
      text = text.to_s.squish.first(MAX_INPUT)
      return if @api_key.blank? || text.blank?

      json = @cache.fetch([ "search-interpreter", @model, text.downcase ], expires_in: 30.days, skip_nil: true) { complete(text) }
      json && parse(json)
    end

    private

    def complete(text)
      response = Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == "https", open_timeout: 3, read_timeout: 10) do |http|
        request = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{@api_key}")
        request.body = { model: @model, temperature: 0, max_tokens: 300,
                         messages: [ { role: "system", content: prompt }, { role: "user", content: text } ] }.to_json
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("Search interpreter: HTTP #{response.code} from #{@uri.host}")
        return
      end

      content = JSON.parse(response.body).dig("choices", 0, "message", "content").to_s
      content[/\{.*\}/m]
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      Rails.logger.warn("Search interpreter failed: #{e.class}: #{e.message}")
      nil
    end

    def prompt
      <<~PROMPT
        You turn a hotel search typed on a travel site into JSON. The visitor wants to stay close to something.
        The text can be in any language and may have typos. Reply with one JSON object and nothing else:
        {"place": string or null, "anchors": [{"name": string, "local_name": string or null, "kind": string or null}],
         "kinds": [string], "max_walk_minutes": integer or null, "property_kinds": [string]}
        - place: the city, island or region meant, in English, also when only implied (Eiffel Tower → "Paris").
          When it lies in one of our destinations below, use that destination's name exactly.
        - anchors: at most 2 specific named places to stay near. name in English, local_name as locals write it.
        - kinds: kinds of place wanted when none is named ("near a beach" → ["beach"]). Allowed kinds:
          #{Landmark::KINDS.join(', ')}.
        - max_walk_minutes: only when the visitor gives a time or distance (500 m ≈ 6 minutes).
        - property_kinds: only when asked for. Allowed: #{Property::KINDS.join(', ')}.
        Our destinations: #{Destination.published.ordered.pluck(:name).join(', ').presence || 'none yet'}.
      PROMPT
    end

    def parse(json)
      data = JSON.parse(json)
      return unless data.is_a?(Hash)

      anchors = Array(data["anchors"]).select { |anchor| anchor.is_a?(Hash) && anchor["name"].is_a?(String) }.first(2).map do |anchor|
        { name: anchor["name"].squish.first(100), local_name: anchor["local_name"].is_a?(String) ? anchor["local_name"].squish.first(100) : nil,
          kind: anchor["kind"].presence_in(Landmark::KINDS) }
      end
      minutes = Integer(data["max_walk_minutes"], exception: false) if data["max_walk_minutes"].is_a?(Numeric)
      Result.new(
        place: data["place"].is_a?(String) ? data["place"].squish.first(100).presence : nil,
        anchors:,
        kinds: Array(data["kinds"]).select { |kind| Landmark::KINDS.include?(kind) }.uniq,
        max_minutes: minutes&.clamp(1, 30),
        property_kinds: Array(data["property_kinds"]).select { |kind| Property::KINDS.include?(kind) }.uniq
      )
    rescue JSON::ParserError
      nil
    end
  end
end
