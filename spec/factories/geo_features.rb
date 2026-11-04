FactoryBot.define do
  factory :water_feature do
    osm_type { "way" }
    sequence(:osm_id) { |n| 1_000 + n }
    kind { "sea" }
    geom { east_west_line(north_m: 100) }
  end

  factory :beach do
    osm_type { "way" }
    sequence(:osm_id) { |n| 2_000 + n }
    surface { "sand" }
    geom { box(south_m: 10, north_m: 100) }
  end

  factory :road_segment do
    sequence(:osm_id) { |n| 3_000 + n }
    category { "road" }
    highway { "residential" }
    geom { east_west_line(north_m: 30) }
  end

  factory :landmark do
    destination
    osm_type { "node" }
    sequence(:osm_id) { |n| 4_000 + n }
    kind { "attraction" }
    sequence(:name) { |n| "Sample Sight #{n}" }
    geom { point_at(north_m: 300) }
    measured_at { Time.current }

    trait :searched do
      source { "search" }
      measured_at { nil }
    end
  end
end
