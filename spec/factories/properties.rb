FactoryBot.define do
  factory :property do
    destination
    sequence(:name) { |n| "Sample Hotel #{n}" }
    kind { "hotel" }
    latitude { GeoHelpers::BASE_LAT }
    longitude { GeoHelpers::BASE_LON }

    # Waterfront result: given any of these, a Verifications::Waterfront is
    # created with the property.
    transient do
      waterfront_category { nil }
      distance_to_water_m { nil }
      water_kind { nil }
      beach_surface { nil }
      distance_to_beach_m { nil }
      crosses_road { false }
      crosses_promenade { false }
    end

    after(:create) do |property, evaluator|
      next unless evaluator.waterfront_category || evaluator.distance_to_water_m

      # A classification job run inline may already have created it.
      verification = property.waterfront || property.build_waterfront
      verification.update!(
        category: evaluator.waterfront_category || "unknown", distance_m: evaluator.distance_to_water_m,
        measured_at: Time.current,
        water_kind: evaluator.water_kind, beach_surface: evaluator.beach_surface,
        distance_to_beach_m: evaluator.distance_to_beach_m, crosses_road: evaluator.crosses_road,
        crosses_promenade: evaluator.crosses_promenade
      )
      property.reload
    end

    trait :hidden do
      hidden_at { Time.current }
    end

    trait :direct do
      waterfront_category { "direct" }
      distance_to_water_m { 20 }
      water_kind { "sea" }
    end

    trait :near do
      waterfront_category { "near" }
      distance_to_water_m { 80 }
      water_kind { "sea" }
    end

    trait :walkable do
      waterfront_category { "walkable" }
      distance_to_water_m { 250 }
      water_kind { "sea" }
    end

    trait :not_waterfront do
      waterfront_category { "not_waterfront" }
      distance_to_water_m { 700 }
    end
  end
end
