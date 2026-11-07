require "rails_helper"

RSpec.describe Property do
  it "builds lonlat from latitude and longitude" do
    property = create(:property, latitude: 43.3, longitude: 17.02)

    reloaded = described_class.find(property.id)
    expect(reloaded.lonlat.y).to be_within(1e-9).of(43.3)
    expect(reloaded.longitude).to be_within(1e-9).of(17.02)
  end

  it "queues a classification when the coordinates change" do
    property = create(:property)

    expect { property.update!(latitude: 43.31) }.to have_enqueued_job(ClassifyPropertyJob).with(property.id)
    expect { property.update!(name: "Renamed") }.not_to have_enqueued_job(ClassifyPropertyJob)
  end

  describe ".published" do
    it "lists properties measured on the waterfront" do
      waterfront = create(:property, :walkable)
      create(:property, :not_waterfront)
      create(:property) # not measured yet
      create(:property, :direct, :hidden)
      create(:property, :direct, osm_missing_since: 1.day.ago)

      expect(described_class.published).to contain_exactly(waterfront)
      expect(waterfront).to be_listed
      expect(create(:property, :direct, :hidden)).not_to be_listed
    end
  end

  describe ".by_waterfront" do
    it "orders by category, then distance" do
      walkable = create(:property, :walkable)
      far_direct = create(:property, :direct, distance_to_water_m: 40)
      close_direct = create(:property, :direct, distance_to_water_m: 10)
      near = create(:property, :near)

      expect(described_class.by_waterfront).to eq([ close_direct, far_direct, near, walkable ])
    end
  end

  describe ".beachfront_claim_conflicts" do
    it "finds properties an OTA calls beachfront that we measured far from the water" do
      conflict = create(:property, :not_waterfront)
      create(:listing, property: conflict, claims_beachfront: true)
      fine = create(:property, :direct)
      create(:listing, property: fine, claims_beachfront: true)

      expect(described_class.beachfront_claim_conflicts).to contain_exactly(conflict)
    end
  end
end
