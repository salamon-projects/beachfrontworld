require "rails_helper"

RSpec.describe Osm::DestinationImport do
  let(:destination) { create(:destination, south: 43.28, west: 16.98, north: 43.32, east: 17.04) }

  it "imports every layer and classifies the properties" do
    counts = described_class.new(destination, client: FakeOverpassClient.new).call

    expect(counts).to eq(coastline: 1, inland_water: 1, beaches: 1, roads: 3, accommodations: 2,
                         removed_features: 0, missing_from_osm: 0, measurement_failures: 0)

    hotel = Property.find_by!(osm_id: 501).waterfront
    expect(hotel).to have_attributes(category: "direct", crosses_promenade: true, crosses_road: false, beach_surface: "sand")
    expect(hotel.distance_m).to be_within(2).of(100)

    apartments = Property.find_by!(osm_id: 502).waterfront
    expect(apartments).to have_attributes(category: "walkable", crosses_road: true)
  end

  it "measures against the current map after removing what OSM no longer has" do
    old_road = create(:road_segment, geom: east_west_line(north_m: 50, half_width_m: 2_000))
    gone = create(:property, destination:, osm_type: "node", osm_id: 599, lonlat: point_at(north_m: 0))

    counts = described_class.new(destination, client: FakeOverpassClient.new).call

    expect(counts).to include(removed_features: 1, missing_from_osm: 1)
    expect(RoadSegment.exists?(old_road.id)).to be(false)
    expect(gone.reload.osm_missing_since).to be_present
  end

  it "keeps measuring the other properties when one fails" do
    real = Waterfront::Classification.instance_method(:call)
    allow_any_instance_of(Waterfront::Classification).to receive(:call) do |classification|
      property = classification.instance_variable_get(:@property)
      raise ActiveRecord::StatementInvalid, "lwgeom error" if property.osm_id == 501

      real.bind_call(classification)
    end

    counts = described_class.new(destination, client: FakeOverpassClient.new).call

    expect(counts[:measurement_failures]).to eq(1)
    expect(Property.find_by!(osm_id: 502).waterfront.category).to eq("walkable")
  end
end
