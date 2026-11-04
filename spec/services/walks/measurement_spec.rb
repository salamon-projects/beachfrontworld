require "rails_helper"

RSpec.describe Walks::Measurement do
  let(:destination) { create(:destination, south: 43.28, west: 16.98, north: 43.32, east: 17.04) }
  let(:client) { FakeOverpassClient.new }
  let(:hotel) { Property.find_by!(osm_id: 501) }
  let(:apartments) { Property.find_by!(osm_id: 502) }
  let(:lighthouse) { destination.landmarks.find_by!(osm_id: 801) }
  let(:castle) { destination.landmarks.find_by!(wikidata: "Q902") }

  before do
    [ Osm::Importers::WalkNetwork, Osm::Importers::Landmarks, Osm::Importers::Accommodations ].each do |importer|
      importer.new(destination, client:).call
    end
  end

  def walk(property, landmark)
    PropertyWalk.find_by!(property:, landmark:)
  end

  it "measures walks along the network, with stairs and busy-road crossings on the way" do
    described_class.new(destination.landmarks).call

    # Up the footway to the promenade, then east along it to the lighthouse.
    expect(walk(hotel, lighthouse)).to have_attributes(busy_crossings: 0, stairs: 0)
    expect(walk(hotel, lighthouse).walk_m).to be_within(5).of(821)

    # East along Coast Road and up the steps.
    expect(walk(apartments, lighthouse)).to have_attributes(busy_crossings: 0, stairs: 1)
    expect(walk(apartments, lighthouse).walk_m).to be_within(5).of(220)

    # West along Coast Road, across Main Road, to the castle grounds.
    expect(walk(apartments, castle)).to have_attributes(busy_crossings: 1, stairs: 0)
    expect(walk(apartments, castle).walk_m).to be_within(10).of(795)
    expect(walk(hotel, castle).walk_m).to be_within(10).of(144)
  end

  it "skips walks over the limit, and removes walks that are no longer confirmed" do
    stale = create(:property, destination:, lonlat: point_at(north_m: 5_000))
    stale.walks.create!(landmark: lighthouse, walk_m: 100, measured_at: 1.day.ago)

    stored = described_class.new(destination.landmarks, config: Walks.config.merge(max_walk_m: 500)).call

    riva = destination.landmarks.find_by!(name: "Riva")
    expect(PropertyWalk.where(property: hotel).map(&:landmark)).to contain_exactly(castle, riva)
    expect(stale.walks.reload).to be_empty
    expect(stored).to eq(PropertyWalk.count)
  end

  it "can measure only some properties" do
    described_class.new(destination.landmarks).call
    hotel.walks.update_all(walk_m: 1)

    described_class.new(destination.landmarks).call(property_ids: [ apartments.id ])

    expect(hotel.walks.pluck(:walk_m)).to all(eq(1))
    expect(apartments.walks.count).to be_positive
  end

  describe Walks::Route do
    it "traces the measured walk over the network" do
      Walks::Measurement.new(destination.landmarks).call

      lines = Walks::Route.new(walk(apartments, lighthouse), cache: ActiveSupport::Cache::NullStore.new).lines

      # From the apartments' end of Coast Road, then up the steps to the promenade.
      expect(lines.size).to eq(1)
      expect(lines.first).to include([ 43.2999, 17.03 ], [ 43.3002, 17.03 ])
      expect(lines.first.map(&:last).min).to be > 17.023
    end
  end
end
