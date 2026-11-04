require "rails_helper"

RSpec.describe MeasureLandmarkJob do
  let(:destination) { create(:destination, south: 43.28, west: 16.98, north: 43.32, east: 17.04) }
  let(:client) { FakeOverpassClient.new }
  let(:landmark) { create(:landmark, :searched, destination:, geom: point_at(north_m: 150)) }

  before { allow(Osm::OverpassClient).to receive(:new).and_return(client) }

  it "fetches the map around the landmark, measures the walks to it, then queues the waterfront" do
    described_class.perform_now(landmark.id)

    expect(MeasureAreaJob).to have_been_enqueued.with(landmark.id, match_array(Property.where(osm_id: [ 501, 502 ]).ids))
    expect(ClassifyPropertyJob).not_to have_been_enqueued

    expect(landmark.reload).to be_measured
    expect(landmark.walks.map(&:property).map(&:osm_id)).to contain_exactly(501, 502)
    expect(MapArea.covers?(landmark.walk_area)).to be(true)
    expect(Property.find_by!(osm_id: 501).destination).to eq(destination)
  end

  it "measures in stages the first time: the stays, the walks nearby, then the rest" do
    walks_before_full_network = nil
    allow(client).to receive(:query).and_wrap_original do |original, ql|
      walks_before_full_network = landmark.walks.reload.map(&:walk_m) if ql.include?("highway") && client.queries.size == 2
      original.call(ql)
    end

    described_class.perform_now(landmark.id)

    near, full = landmark.walk_area(described_class::NEAR_WALK_M), landmark.walk_area
    expect(client.queries.map { |ql| ql[/\(([\d.,]+)\);/, 1] })
      .to eq([ full.join(","), near.join(","), full.join(",") ])
    expect(client.queries.first).to include('"tourism"')
    expect(walks_before_full_network).to be_present.and all(be <= described_class::NEAR_WALK_M)
  end

  it "only measures when the map around it is fresh" do
    MapArea.record!(landmark.walk_area)

    expect { described_class.perform_now(landmark.id) }.not_to have_enqueued_job(MeasureAreaJob)
    expect(client.queries).to be_empty
    expect(landmark.reload).to be_measured
  end

  it "records a failure, for the landmark page to offer another try" do
    landmark.update!(measure_requested_at: 1.minute.ago)
    allow(client).to receive(:query).and_raise(Osm::OverpassClient::Error, "busy")

    described_class.perform_now(landmark.id)

    expect(landmark.reload).to have_attributes(measured?: false, measuring?: false, measure_failed?: true)
  end
end

RSpec.describe MeasureAreaJob do
  before { allow(Osm::OverpassClient).to receive(:new).and_return(FakeOverpassClient.new) }

  it "fetches water and roads around the landmark and measures the waterfront of the properties there" do
    landmark = create(:landmark, :searched, geom: point_at)
    property = create(:property, destination: landmark.destination, lonlat: point_at(north_m: -10))

    described_class.perform_now(landmark.id)

    expect(WaterFeature.count).to be_positive
    expect(RoadSegment.count).to be_positive
    expect(property.reload.waterfront).to be_present
  end

  it "measures the walks from the properties it brought in to the other landmarks within reach" do
    destination = create(:destination, south: 43.28, west: 16.98, north: 43.32, east: 17.04)
    Osm::Importers::WalkNetwork.new(destination, client: FakeOverpassClient.new).call
    searched = create(:landmark, :searched, destination:, geom: point_at(north_m: 150), measured_at: Time.current)
    other = create(:landmark, destination:, geom: point_at(north_m: 150, east_m: 200))
    far = create(:landmark, destination:, geom: point_at(north_m: 40_000))
    property = create(:property, destination:, lonlat: point_at(north_m: 60))

    described_class.perform_now(searched.id, [ property.id ])

    expect(property.walks.map(&:landmark)).to contain_exactly(searched, other)
    expect(far.walks).to be_empty
  end
end
