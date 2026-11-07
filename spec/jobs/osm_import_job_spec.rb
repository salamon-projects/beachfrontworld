require "rails_helper"

RSpec.describe OsmImportJob do
  let(:destination) { create(:destination, south: 43.28, west: 16.98, north: 43.32, east: 17.04) }
  let(:run) { destination.import_runs.create!(source: "osm") }

  it "imports the destination and records progress and counts" do
    allow(Osm::OverpassClient).to receive(:new).and_return(FakeOverpassClient.new)
    steps = []
    allow_any_instance_of(ImportRun).to receive(:progress!).and_wrap_original do |original, step, done, total|
      steps << [ step, done, total ]
      original.call(step, done, total)
    end

    described_class.perform_now(destination.id, run.id)

    expect(run.reload).to have_attributes(status: "succeeded", attempts: 1, error: nil)
    expect(run.counts).to include("coastline" => 1, "accommodations" => 2, "measurement_failures" => 0)
    expect(run.started_at).to be_present
    expect(run.finished_at).to be_present
    expect(steps.map(&:first)).to start_with(%w[coastline inland_water beaches roads accommodations])
    expect(steps.last).to eq([ "measuring 0/2", 5, 6 ])
  end

  it "creates its own run when scheduled without one" do
    allow(Osm::OverpassClient).to receive(:new).and_return(FakeOverpassClient.new)

    expect { described_class.perform_now(destination.id) }.to change(ImportRun, :count).by(1)
    expect(destination.import_runs.sole).to be_succeeded
  end

  it "shows a retry when Overpass is unavailable and retries later" do
    allow(Osm::DestinationImport).to receive(:new).and_raise(Osm::OverpassClient::Error, "Overpass is busy.")

    expect { described_class.perform_now(destination.id, run.id) }.to have_enqueued_job(described_class).with(destination.id, run.id)
    expect(run.reload).to be_retrying
    expect(run.error).to include("Overpass is busy.", "Trying again at")
  end

  it "records other errors as failures" do
    allow(Osm::DestinationImport).to receive(:new).and_raise(ArgumentError, "bad bbox")

    expect { described_class.perform_now(destination.id, run.id) }.to raise_error(ArgumentError)
    expect(run.reload).to have_attributes(status: "failed", error: "ArgumentError: bad bbox")
  end
end
