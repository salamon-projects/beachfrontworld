module Search
  # Decides where a free-text search leads: one landmark, a choice between
  # several, a kind of place (beaches, pedestrian streets) in a destination,
  # a destination, or a place we have not measured yet, to look up on the
  # map (:locate, with queries for Search::Locator).
  class Resolver
    # A match this much better than the next one is taken without asking.
    CLEAR_LEAD = 0.1
    # Words that never name a place, ignored when no language model helps.
    FILLER = %w[a an the in at on near by close to next from of and with for hotel hotels stay stays
                apartment apartments room rooms place walk walking distance best cheap quiet].freeze

    Outcome = Data.define(:status, :landmark, :landmarks, :destination, :destinations, :kind, :max_minutes,
                          :property_kind, :place, :queries) do
      def self.build(status, **attributes)
        new(status:, **members.excluding(:status).index_with(nil), **attributes)
      end
    end

    def initialize(interpreter: Interpreter.new)
      @interpreter = interpreter
    end

    def call(text)
      @text = text.to_s.squish
      return Outcome.build(:none) if @text.blank?

      @interpretation = @interpreter.call(@text)
      @destination = destination_match

      landmarks = candidates
      if landmarks.any?
        return outcome(:landmark, landmark: landmarks.first) if clear_winner?(landmarks)

        return outcome(:choices, landmarks: landmarks.first(6))
      end

      queries = locate_queries
      return outcome(:locate, queries:, destination: @destination, place: @interpretation&.place) if queries.any?

      kind = @interpretation&.kinds&.first
      if kind
        return outcome(:kind, destination: @destination, kind:) if @destination

        with_kind = Destination.published.ordered.where(id: Landmark.where(kind:).select(:destination_id))
        return outcome(:choose_destination, destinations: with_kind.to_a, kind:) if with_kind.any?
      end
      return outcome(:destination, destination: @destination) if @destination

      Outcome.build(:none, place: @interpretation&.place)
    end

    private

    def outcome(status, **attributes)
      Outcome.build(status, max_minutes: @interpretation&.max_minutes,
                            property_kind: @interpretation&.property_kinds&.first, **attributes)
    end

    def published_landmarks
      scope = Landmark.visible
      @destination ? scope.where(destination: @destination) : scope
    end

    # Landmarks matching the names the model found, or, without a model,
    # the whole text or the words in it that could name a place. A place in
    # a town none of our destinations is named after is looked up on the
    # map instead, so "Opera, Budapest" does not lead to the Paris Opera.
    def candidates
      return [] if @interpretation&.place.present? && @destination.nil?

      names = @interpretation&.anchor_names.presence || (fallback_names unless @interpretation&.kinds&.any?) || []
      names.flat_map { |name| published_landmarks.search(name).limit(6).to_a }
           .sort_by { |landmark| [ -landmark.search_score, -landmark.prominence ] }
           .uniq(&:id)
    end

    # What to ask the map for: the places the model named, in their town,
    # or the words that could name a place.
    def locate_queries
      town = @interpretation&.place || @destination&.name
      if @interpretation&.anchors&.any?
        @interpretation.anchors.flat_map { |anchor| [ anchor[:name], anchor[:local_name] ] }.compact_blank
                       .map { |name| [ name, town ].compact.join(", ") }
      elsif @interpretation.nil? && fallback_names.any?
        [ [ fallback_names.first, town ].compact.join(", ") ]
      else
        []
      end
    end

    def fallback_names
      words = Landmark.normalize(@text).split - FILLER - destination_words
      return [] if words.empty?

      [ words.join(" ") ] + (words.size > 1 ? words.each_cons(2).map { |pair| pair.join(" ") } : [])
    end

    def clear_winner?(landmarks)
      landmarks.size == 1 || landmarks.first.search_score - landmarks.second.search_score >= CLEAR_LEAD
    end

    # The destination the model placed the search in, or one whose name
    # (or its first word: "Makarska" for "Makarska Riviera") is in the text.
    def destination_match
      place = Landmark.normalize(@interpretation&.place)
      text = " #{Landmark.normalize(@text)} "
      Destination.published.ordered.find do |destination|
        name = Landmark.normalize(destination.name)
        name == place || text.include?(" #{name} ") || text.include?(" #{name.split.first} ")
      end
    end

    def destination_words
      @destination ? Landmark.normalize(@destination.name).split : []
    end
  end
end
