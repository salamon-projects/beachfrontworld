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
    summary: "Sunny east coast from Faliraki to Lindos, with sandy and pebble bays." },
  { name: "Zakynthos south", country_code: "GR", sea_name: "Ionian Sea", zoom: 12,
    south: 37.69, west: 20.83, north: 37.75, east: 20.92,
    summary: "Laganas Bay on Zakynthos, from Laganas to Kalamaki." },
  { name: "Naxos west coast", country_code: "GR", sea_name: "Aegean Sea", zoom: 12,
    south: 37.03, west: 25.35, north: 37.11, east: 25.41,
    summary: "Sandy beaches south of Naxos town: Agios Georgios, Agios Prokopios, Agia Anna and Plaka." },
  { name: "Hersonissos & Malia", country_code: "GR", sea_name: "Sea of Crete", zoom: 12,
    south: 35.28, west: 25.35, north: 35.33, east: 25.48,
    summary: "Crete's north-coast resort strip from Hersonissos to Malia." },
  { name: "Crikvenica Riviera", country_code: "HR", sea_name: "Adriatic Sea", zoom: 12,
    south: 45.12, west: 14.65, north: 45.20, east: 14.80,
    summary: "Kvarner coast from Crikvenica and Selce to Novi Vinodolski." },
  { name: "Brač", country_code: "HR", sea_name: "Adriatic Sea", zoom: 11,
    south: 43.25, west: 16.38, north: 43.42, east: 16.90,
    summary: "Island of Bol's Zlatni Rat beach, Supetar and quiet harbour villages." },
  { name: "Dubrovnik", country_code: "HR", sea_name: "Adriatic Sea", zoom: 13,
    south: 42.63, west: 18.05, north: 42.67, east: 18.13,
    summary: "Old town, Lapad and Babin Kuk, with rocky shores and small beaches." },
  { name: "Barcelona", country_code: "ES", sea_name: "Mediterranean Sea", zoom: 13,
    south: 41.37, west: 2.15, north: 41.405, east: 2.195,
    summary: "City beaches from Barceloneta to Nova Icària, a short walk from the old town." },
  { name: "Lloret de Mar & Tossa", country_code: "ES", sea_name: "Mediterranean Sea", zoom: 12,
    south: 41.68, west: 2.80, north: 41.73, east: 2.95,
    summary: "Costa Brava resort coast of sandy town beaches and rocky coves, from Lloret de Mar to Tossa de Mar." },
  { name: "Alcúdia Bay", country_code: "ES", sea_name: "Mediterranean Sea", zoom: 12,
    south: 39.76, west: 3.08, north: 39.86, east: 3.18,
    summary: "Mallorca's long shallow sandy bay, from Port d'Alcúdia to Can Picafort." },
  { name: "Benidorm", country_code: "ES", sea_name: "Mediterranean Sea", zoom: 13,
    south: 38.52, west: -0.16, north: 38.56, east: -0.08,
    summary: "Costa Blanca high-rise resort between Levante and Poniente beaches." },
  { name: "Marbella", country_code: "ES", sea_name: "Mediterranean Sea", zoom: 12,
    south: 36.47, west: -4.98, north: 36.52, east: -4.82,
    summary: "Costa del Sol seafront from Puerto Banús to Marbella old town." },
  { name: "Rimini & Riccione", country_code: "IT", sea_name: "Adriatic Sea", zoom: 12,
    south: 43.98, west: 12.52, north: 44.10, east: 12.70,
    summary: "The Romagna Riviera's wide sandy beaches, lined with beach clubs and seafront hotels." },
  { name: "Amalfi Coast", country_code: "IT", sea_name: "Tyrrhenian Sea", zoom: 12,
    south: 40.61, west: 14.47, north: 40.66, east: 14.62,
    summary: "Cliffside villages from Positano to Amalfi, with small pebble beaches." },
  { name: "Taormina & Giardini Naxos", country_code: "IT", sea_name: "Ionian Sea", zoom: 13,
    south: 37.81, west: 15.25, north: 37.87, east: 15.31,
    summary: "Sicilian coast below Taormina, from Isola Bella to the sandy bay of Giardini Naxos." },
  { name: "Villasimius", country_code: "IT", sea_name: "Mediterranean Sea", zoom: 12,
    south: 39.10, west: 9.46, north: 39.16, east: 9.56,
    summary: "South-east Sardinia's white sand beaches and turquoise coves." }
].freeze

DESTINATIONS.each_with_index do |attrs, position|
  destination = Destination.find_or_initialize_by(name: attrs[:name])
  next if destination.persisted?

  destination.update!(attrs.merge(position:, published: false))
end

load Rails.root.join("db/seeds/demo.rb") if Rails.env.development?
