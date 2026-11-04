require "rails_helper"

RSpec.describe "OSM importers" do
  let(:destination) { create(:destination, south: 43.28, west: 16.98, north: 43.32, east: 17.04) }
  let(:client) { FakeOverpassClient.new }

  def run(importer)
    importer.new(destination, client:).call
  end

  it "queries the destination's bounding box" do
    run(Osm::Importers::Coastline)

    expect(client.queries.last).to include('way["natural"="coastline"](43.28,16.98,43.32,17.04);').and include("out geom;")
  end

  it "imports coastline ways as sea and skips degenerate ones" do
    expect(run(Osm::Importers::Coastline)).to eq(1)

    feature = WaterFeature.sole
    expect(feature).to have_attributes(kind: "sea", osm_type: "way", osm_id: 101)
    expect(feature.geom.num_points).to eq(3)
  end

  it "is idempotent" do
    2.times { run(Osm::Importers::Coastline) }

    expect(WaterFeature.count).to eq(1)
  end

  it "imports closed lake polygons" do
    expect(run(Osm::Importers::InlandWater)).to eq(1)
    expect(WaterFeature.sole).to have_attributes(kind: "lake", name: "Test Lake")
  end

  it "imports beaches with a normalised surface" do
    run(Osm::Importers::Beaches)

    expect(Beach.sole).to have_attributes(name: "Sample Beach", surface: "sand")
  end

  it "categorises roads, skipping tunnels and parking aisles" do
    expect(run(Osm::Importers::Roads)).to eq(3)

    expect(RoadSegment.pluck(:osm_id, :category)).to contain_exactly([ 401, "road" ], [ 402, "promenade" ], [ 403, "rail" ])
  end

  describe "features OSM no longer has" do
    # The box's north edge is 2,224 m north of the base point.
    it "removes them inside the box, but keeps those near its edge or outside it" do
      create(:road_segment, osm_id: 990, geom: east_west_line(north_m: 500))
      create(:road_segment, osm_id: 991, geom: east_west_line(north_m: 2_180))
      create(:road_segment, osm_id: 992, geom: east_west_line(north_m: 3_000))

      importer = Osm::Importers::Roads.new(destination, client:)
      importer.call

      expect(importer.removed).to eq(1)
      expect(RoadSegment.pluck(:osm_id)).to contain_exactly(401, 402, 403, 991, 992)
    end

    it "keeps what a layer returns again" do
      run(Osm::Importers::Roads)
      run(Osm::Importers::Roads)

      expect(RoadSegment.count).to eq(3)
    end

    it "only removes the features of its own layer" do
      create(:water_feature, osm_id: 990, kind: "sea", geom: east_west_line(north_m: 500))
      create(:water_feature, osm_id: 991, kind: "lake", geom: box(south_m: 600, north_m: 700))

      run(Osm::Importers::Coastline)

      expect(WaterFeature.pluck(:osm_id)).to contain_exactly(101, 991)
    end

    it "removes nothing when a layer comes back empty" do
      create(:beach, geom: box(south_m: 600, north_m: 700))
      empty = instance_double(Osm::OverpassClient, query: [])

      Osm::Importers::Beaches.new(destination, client: empty).call

      expect(Beach.count).to eq(1)
    end
  end

  describe Osm::Importers::WalkNetwork do
    it "splits walkable ways into edges between nodes and skips ways closed to walkers" do
      expect(run(described_class)).to eq(8)

      expect(WalkEdge.where(osm_way_id: 701).order(:id).pluck(:source, :target))
        .to eq([ [ 9001, 9002 ], [ 9002, 9022 ], [ 9022, 9004 ] ])
      expect(WalkEdge.where(osm_way_id: [ 706, 707, 708 ])).to be_empty
      expect(WalkEdge.find_by!(osm_way_id: 705)).to have_attributes(steps: true, busy: false)
      expect(WalkEdge.find_by!(osm_way_id: 704)).to have_attributes(busy: true)
      expect(WalkEdge.find_by!(osm_way_id: 703).length_m).to be_within(0.5).of(33.4)
      expect(WalkVertex.where(busy: true).pluck(:node_id)).to contain_exactly(9021, 9022)
      expect(WalkVertex.count).to eq(8)
    end

    it "queries a big box in tiles and keeps each way once" do
      described_class.new(destination, client:, bbox: [ 43.28, 16.98, 43.32, 17.12 ]).call

      tiles = client.queries.map { |ql| ql[/\(([\d.,]+)\);out geom/, 1].split(",").map(&:to_f) }
      expect(tiles).to eq([ [ 43.28, 16.98, 43.32, 17.05 ], [ 43.28, 17.05, 43.32, 17.12 ] ])
      expect(WalkEdge.count).to eq(8)
    end

    it "fills in the shared network box by box, replacing ways it fetches again" do
      neighbour = create(:destination, south: 43.32, west: 16.98, north: 43.36, east: 17.04)
      WalkEdge.create!(osm_way_id: 799, source: 1, target: 2, highway: "footway", geom: east_west_line(north_m: 10_000))
      2.times { run(described_class) }

      described_class.new(neighbour, client:, bbox: neighbour.bbox).call

      expect(WalkEdge.count).to eq(8 + 1)
      expect(WalkVertex.distinct.count(:node_id)).to eq(WalkVertex.count)
    end

    it "removes ways inside the box that OSM no longer has, and keeps the network when the answer is empty" do
      WalkEdge.create!(osm_way_id: 799, source: 1, target: 2, highway: "footway", geom: east_west_line(north_m: 500))
      importer = described_class.new(destination, client:)
      importer.call
      expect(importer.removed).to eq(1)

      described_class.new(destination, client: instance_double(Osm::OverpassClient, query: [])).call

      expect(WalkEdge.count).to eq(8)
    end

    it "takes a node's busy flag from the ways fetched with it inside the box" do
      run(described_class)
      WalkVertex.find_by!(node_id: 9001).update!(busy: true)

      run(described_class)

      expect(WalkVertex.where(busy: true).pluck(:node_id)).to contain_exactly(9021, 9022)
    end
  end

  describe Osm::Importers::Landmarks do
    it "imports notable places, joining the ways of a street and duplicates of one place" do
      expect(run(described_class)).to eq(5)

      lighthouse = destination.landmarks.find_by!(osm_id: 801)
      expect(lighthouse).to have_attributes(kind: "attraction", name: "Sample Lighthouse", local_name: "Svjetionik",
                                            slug: "sample-lighthouse", wikidata: "Q901")
      expect(lighthouse.names).to include("hu" => "Minta világítótorony")
      expect(lighthouse.prominence).to eq(3 + 20 + 20)

      street = destination.landmarks.find_by!(kind: "pedestrian_street")
      expect(street).to have_attributes(name: "Riva", osm_id: 802)
      expect(street.geom.num_geometries).to eq(2)

      castle = destination.landmarks.find_by!(wikidata: "Q902")
      expect(castle).to have_attributes(kind: "historic", osm_type: "way", osm_id: 806)

      beach = destination.landmarks.find_by!(kind: "beach")
      expect(beach).to have_attributes(name: nil, slug: "beach-804", display_name: "a beach")

      expect(destination.landmarks.find_by(osm_id: 805)).to be_nil
      expect(destination.landmarks.find_by!(osm_id: 808).kind).to eq("station")
    end

    it "keeps slugs on re-import and removes landmarks OSM no longer has" do
      run(described_class)
      gone = destination.landmarks.create!(osm_type: "node", osm_id: 899, kind: "museum", name: "Closed Museum",
                                           geom: point_at(north_m: 100))

      run(described_class)

      expect(Landmark.exists?(gone.id)).to be(false)
      expect(destination.landmarks.find_by!(osm_id: 801).slug).to eq("sample-lighthouse")
      expect(destination.landmarks.count).to eq(5)
    end
  end

  describe Osm::Importers::Accommodations do
    it "creates pending properties from named nodes and ways" do
      expect(run(described_class)).to eq(2)

      hotel = Property.find_by!(osm_type: "node", osm_id: 501)
      expect(hotel).to have_attributes(name: "Hotel Sample Bay", kind: "hotel", stars: 4,
                                       address: "Obala 1, Sampleville", website: "https://hotel-sample-bay.example",
                                       destination:)
      expect(hotel.footprint).to be_nil
      expect(hotel).not_to be_reviewed

      apartments = Property.find_by!(osm_type: "way", osm_id: 502)
      expect(apartments).to have_attributes(kind: "apartment", website: nil)
      expect(apartments.footprint).to be_present
      expect(apartments.lonlat.x).to be_within(1e-6).of(17.0280)
    end

    it "keeps the geometry and name of reviewed properties on re-import" do
      run(described_class)
      hotel = Property.find_by!(osm_id: 501)
      hotel.update!(name: "Hotel Sample Bay & Spa", latitude: 43.3002, longitude: 17.0201, reviewed_at: Time.current)

      run(described_class)

      expect(hotel.reload).to have_attributes(name: "Hotel Sample Bay & Spa", latitude: 43.3002)
    end

    it "keeps details edited on reviewed properties and only fills blanks" do
      run(described_class)
      hotel = Property.find_by!(osm_id: 501)
      hotel.update!(address: "Obala 1a, Sampleville", stars: nil, reviewed_at: Time.current)

      run(described_class)

      expect(hotel.reload).to have_attributes(address: "Obala 1a, Sampleville", stars: 4)
    end

    it "updates the name of properties still pending review" do
      run(described_class)
      Property.find_by!(osm_id: 501).update!(name: "Old name")

      run(described_class)

      expect(Property.find_by!(osm_id: 501).name).to eq("Hotel Sample Bay")
    end

    it "flags properties OSM no longer returns, and clears the flag when they are back" do
      run(described_class)
      gone = create(:property, :direct, destination:, osm_type: "node", osm_id: 599, lonlat: point_at(north_m: 300))
      manual = create(:property, destination:, lonlat: point_at(north_m: 300))
      elsewhere = create(:property, destination:, osm_type: "node", osm_id: 598, lonlat: point_at(north_m: 3_000))

      travel_to Time.zone.local(2026, 11, 2, 3, 0) do
        run(described_class)
      end

      expect(gone.reload.osm_missing_since).to eq(Time.zone.local(2026, 11, 2, 3, 0))
      expect(Property.missing_from_osm).to contain_exactly(gone)
      expect(gone).not_to be_listed
      expect([ manual, elsewhere ].map { |property| property.reload.osm_missing_since }).to all(be_nil)

      run(described_class)
      expect(gone.reload.osm_missing_since).to eq(Time.zone.local(2026, 11, 2, 3, 0))

      hotel = Property.find_by!(osm_id: 501)
      hotel.update_columns(osm_missing_since: 1.day.ago)
      run(described_class)
      expect(hotel.reload.osm_missing_since).to be_nil
    end

    it "flags nothing when the query comes back empty" do
      run(described_class)

      described_class.new(destination, client: instance_double(Osm::OverpassClient, query: [])).call

      expect(Property.missing_from_osm).to be_empty
    end

    it "updates the geometry of properties still pending review" do
      run(described_class)
      hotel = Property.find_by!(osm_id: 501)
      hotel.update!(latitude: 43.4, longitude: 17.0)

      run(described_class)

      expect(hotel.reload.latitude).to be_within(1e-9).of(43.30010)
    end
  end
end
