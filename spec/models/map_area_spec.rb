require "rails_helper"

RSpec.describe MapArea do
  it "tells whether fresh areas together cover a box" do
    described_class.record!([ 43.0, 16.0, 43.1, 16.1 ])
    described_class.record!([ 43.1, 16.0, 43.2, 16.1 ])
    described_class.record!([ 43.0, 16.1, 43.2, 16.2 ], fetched_at: 40.days.ago)

    expect(described_class.covers?([ 43.05, 16.02, 43.15, 16.08 ])).to be(true)
    expect(described_class.covers?([ 43.05, 16.02, 43.15, 16.15 ])).to be(false)
    expect(described_class.covers?([ 43.05, 16.02, 43.15, 16.15 ], since: 50.days.ago)).to be(true)
    expect(described_class.covers?([ 50.0, 10.0, 50.1, 10.1 ])).to be(false)
  end
end
