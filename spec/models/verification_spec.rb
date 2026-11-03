require "rails_helper"

RSpec.describe Verification do
  let(:property) { create(:property) }

  it "keeps one result per property, type and subject" do
    create(:waterfront_verification, property:)

    duplicate = build(:waterfront_verification, property:)
    expect(duplicate).not_to be_valid
    expect(build(:waterfront_verification, property:, subject: "north-wing")).to be_valid
  end

  describe Verifications::Waterfront do
    it "accepts only its own categories" do
      expect(build(:waterfront_verification, category: "direct")).to be_valid
      expect(build(:waterfront_verification, category: "sea_view")).not_to be_valid
    end

    it "is listed only in a listed category" do
      expect(build(:waterfront_verification, category: "near")).to be_listed
      expect(build(:waterfront_verification, category: "not_waterfront")).not_to be_listed
    end

    it "keeps measurement details in the evidence" do
      verification = create(:waterfront_verification, crosses_road: true, beach_surface: "pebble", water_point: [ 17.0, 43.3 ])

      reloaded = described_class.find(verification.id)
      expect(reloaded).to be_crosses_road
      expect(reloaded).not_to be_crosses_promenade
      expect(reloaded.beach_surface).to eq("pebble")
      expect(reloaded.water_point).to eq([ 17.0, 43.3 ])
      expect(reloaded.evidence).to include("crosses_road" => true, "beach_surface" => "pebble")
    end

    it "names the destination's sea when the water has no name" do
      verification = create(:waterfront_verification, water_kind: "sea")

      expect(verification.water_display_name).to eq("the Adriatic Sea")
      verification.water_name = "Lake Bled"
      expect(verification.water_display_name).to eq("Lake Bled")
    end

    it "derives its key for translations" do
      expect(described_class.key).to eq("waterfront")
    end
  end
end
