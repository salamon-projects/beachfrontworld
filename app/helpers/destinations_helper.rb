module DestinationsHelper
  SEAS = %w[adriatic aegean ionian tyrrhenian crete mediterranean].freeze

  # The colour family of a coast card ("Sea of Crete" → "crete").
  def sea_key(destination)
    name = destination.sea_name.to_s.downcase
    SEAS.find { |sea| name.include?(sea) } || "default"
  end
end
