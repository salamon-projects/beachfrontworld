# Fictional demo data for development only: a straight coastline, a beach, a
# road and a promenade around a made-up bay, a small grid of streets to walk
# (with a busy avenue and a flight of steps), a few landmarks, and sample
# properties at different distances. Nothing here describes a real place or
# business.

EARTH_RADIUS_M = 6_371_008.8
BASE = { lat: 43.30, lon: 17.02 }.freeze

def demo_offset(north_m, east_m = 0)
  dlat = north_m / EARTH_RADIUS_M * 180 / Math::PI
  dlon = east_m / (EARTH_RADIUS_M * Math.cos(BASE[:lat] * Math::PI / 180)) * 180 / Math::PI
  [ BASE[:lon] + dlon, BASE[:lat] + dlat ]
end

def demo_line(north_m, from_east: -900, to_east: 900)
  Geo.line([ demo_offset(north_m, from_east), demo_offset(north_m, to_east) ])
end

def demo_box(south_m, north_m, west_m, east_m)
  Geo.polygon([ demo_offset(south_m, west_m), demo_offset(south_m, east_m),
                demo_offset(north_m, east_m), demo_offset(north_m, west_m) ])
end

return if Destination.exists?(slug: "demo-bay")

ActiveRecord::Base.transaction do
  lon_min, lat_min = demo_offset(-1500, -2000)
  lon_max, lat_max = demo_offset(1500, 2000)
  demo = Destination.create!(name: "Demo Bay", slug: "demo-bay", country_code: "HR", sea_name: "Adriatic Sea",
                             south: lat_min, west: lon_min, north: lat_max, east: lon_max, zoom: 15,
                             position: 99, published: true,
                             summary: "Fictional sample data for development. Not a real place.")

  WaterFeature.create!(osm_type: "demo", osm_id: 1, kind: "sea", geom: demo_line(200))
  Beach.create!(osm_type: "demo", osm_id: 1, name: "Demo Beach", surface: "sand", geom: demo_box(60, 200, -900, 100))
  Beach.create!(osm_type: "demo", osm_id: 2, name: "Demo Pebbles", surface: "pebble", geom: demo_box(170, 200, 100, 900))
  RoadSegment.create!(osm_id: 900_001, category: "road", highway: "residential", name: "Demo Coast Road",
                      geom: demo_line(140, from_east: 100, to_east: 900))
  RoadSegment.create!(osm_id: 900_002, category: "promenade", highway: "footway", name: "Demo Promenade",
                      geom: demo_line(55, from_east: -900, to_east: 100))

  samples = [
    [ "Sample Hotel Azure", "hotel", 4, 52, -500 ],      # behind a promenade on the wide sandy beach
    [ "Sample Beach Apartments", "apartment", nil, 160, 300 ], # over the pebbles, no road
    [ "Sample Villa Rocks", "villa", nil, 185, 700 ],     # right above the pebbles
    [ "Sample Guest House", "guest_house", 3, 110, 500 ], # behind the coast road
    [ "Sample Garden Hotel", "hotel", 3, -20, -100 ],     # a short walk inland
    [ "Sample Inland Inn", "hotel", 2, -700, 0 ]          # inland, across the busy avenue
  ]
  providers = %w[booking expedia agoda]
  samples.each_with_index do |(name, kind, stars, north_m, east_m), index|
    lon, lat = demo_offset(north_m, east_m)
    property = Property.create!(destination: demo, name:, kind:, stars:, latitude: lat, longitude: lon,
                                address: "#{index + 1} Demo Street, Demo Bay")
    providers.first(index.even? ? 3 : 2).each do |provider|
      url = { "booking" => "https://www.booking.com/hotel/hr/#{property.slug}.html",
              "expedia" => "https://www.expedia.com/#{property.slug}.Hotel-Information",
              "agoda" => "https://www.agoda.com/#{property.slug}/hotel/demo-bay-hr.html" }.fetch(provider)
      property.listings.create!(provider:, url:, claims_beachfront: true)
    end
  end

  # Streets in a grid: rows north of the base point, lanes east of it.
  rows = { 140 => "residential", 55 => "footway", -20 => "pedestrian", -400 => "primary", -700 => "residential" }
  lanes = [ -900, -500, -100, 300, 700 ]
  node = ->(north_m, east_m) { 9_000_000 + (rows.keys.index(north_m) * lanes.size) + lanes.index(east_m) }
  rows.each_key do |north_m|
    lanes.each do |east_m|
      lon, lat = demo_offset(north_m, east_m)
      WalkVertex.create!(destination: demo, node_id: node.(north_m, east_m), busy: rows[north_m] == "primary",
                         geom: Geo.point(lon:, lat:))
    end
  end
  edge = lambda do |from, to, highway|
    WalkEdge.create!(destination: demo, osm_way_id: 0, source: node.(*from), target: node.(*to), highway:,
                     busy: highway == "primary", steps: highway == "steps",
                     geom: Geo.line([ demo_offset(*from), demo_offset(*to) ]))
  end
  rows.each { |north_m, highway| lanes.each_cons(2) { |west, east| edge.([ north_m, west ], [ north_m, east ], highway) } }
  lanes.each do |east_m|
    rows.keys.each_cons(2) do |north, south|
      edge.([ north, east_m ], [ south, east_m ], east_m == 300 && north == 140 ? "steps" : "footway")
    end
  end
  demo.walk_edges.update_all("length_m = ST_Length(geom)")

  [ [ "Demo Lighthouse", "attraction", 60, Geo.point(lon: demo_offset(200, 900)[0], lat: demo_offset(200, 900)[1]) ],
    [ "Demo Old Town Square", "square", 40, demo_box(-390, -300, -200, 0) ],
    [ "Demo Walk", "pedestrian_street", 20, Geo.line([ demo_offset(-20, -500), demo_offset(-20, 300) ]) ],
    [ "Demo Beach", "beach", 10, demo_box(60, 200, -900, 100) ],
    [ "Demo Market", "market", 5, Geo.point(lon: demo_offset(-700, 300)[0], lat: demo_offset(-700, 300)[1]) ] ]
    .each_with_index do |(name, kind, prominence, geom), index|
      demo.landmarks.create!(osm_type: "demo", osm_id: index + 1, name:, kind:, prominence:, geom:,
                             names: { "hu" => "#{name} (HU)" })
    end

  demo.properties.find_each { |property| Waterfront::Classification.new(property).call }
  Walks::Measurement.new(demo).call
end

puts "Demo Bay: " + Destination.find_by!(slug: "demo-bay").properties.joins(:waterfront)
  .pluck(:name, "verifications.category", "verifications.distance_m").map { |n, c, d| "#{n}=#{c}(#{d}m)" }.join(", ")
puts "Demo Bay walks: #{PropertyWalk.joins(:landmark).where(landmarks: { destination_id: Destination.find_by!(slug: 'demo-bay').id }).count}"
