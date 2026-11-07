# Launch destinations. Bounding boxes are approximate and can be adjusted in
# the admin; they only decide which OSM data `bin/rails osm:import[slug]`
# fetches. Properties come from that import, never from seeds. Destinations
# start unpublished: publish them in the admin once imported and measured.
#
# In development, `bin/rails db:seed` also loads a small fictional demo bay
# (db/seeds/demo.rb) so the site can be tried without an OSM import.

DESTINATIONS = [
  { name: "Makarska Riviera", country_code: "HR", sea_name: "Adriatic Sea", zoom: 11,
    south: 43.08, west: 16.90, north: 43.40, east: 17.36,
    summary: "Pebble beaches backed by the Biokovo mountains, from Brela to Gradac." },
  { name: "Poreč", country_code: "HR", sea_name: "Adriatic Sea", zoom: 12,
    south: 45.17, west: 13.56, north: 45.29, east: 13.64,
    summary: "Istrian resort town with rocky shores, small coves and long seafront paths." },
  { name: "Hvar", country_code: "HR", sea_name: "Adriatic Sea", zoom: 11,
    south: 43.10, west: 16.38, north: 43.22, east: 16.72,
    summary: "Sunny island of lavender fields, a busy harbour town and quiet bays." },
  { name: "Kassandra", country_code: "GR", sea_name: "Aegean Sea", zoom: 10,
    south: 39.90, west: 23.30, north: 40.25, east: 23.80,
    summary: "The westernmost peninsula of Halkidiki, known for long sandy beaches." },
  { name: "Chania coast", country_code: "GR", sea_name: "Sea of Crete", zoom: 11,
    south: 35.47, west: 23.70, north: 35.54, east: 24.10,
    summary: "Long sandy beaches west of Chania town, from Agia Marina to Platanias." },
  { name: "Rhodes east coast", country_code: "GR", sea_name: "Mediterranean Sea", zoom: 11,
    south: 36.08, west: 28.05, north: 36.36, east: 28.25,
    summary: "Sunny east coast from Faliraki to Lindos, with sandy and pebble bays." }
].freeze

DESTINATIONS.each_with_index do |attrs, position|
  destination = Destination.find_or_initialize_by(name: attrs[:name])
  next if destination.persisted?

  destination.update!(attrs.merge(position:, published: false))
end

load Rails.root.join("db/seeds/demo.rb") if Rails.env.development?
