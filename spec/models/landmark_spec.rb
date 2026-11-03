require "rails_helper"

RSpec.describe Landmark do
  let(:destination) { create(:destination) }

  def landmark(name, **attributes)
    destination.landmarks.create!(osm_type: "node", osm_id: rand(1..10**9), kind: "attraction", name:,
                                  geom: point_at, **attributes)
  end

  describe ".search" do
    it "finds names in any language, without accents and with typos" do
      tower = landmark("Eiffel Tower", local_name: "Tour Eiffel", names: { "hu" => "Eiffel-torony" }, prominence: 80)
      church = landmark("Sagrada Família")
      landmark("Arc de Triomphe")

      expect(described_class.search("eiffel torony")).to eq([ tower ])
      expect(described_class.search("tour eifel")).to eq([ tower ])
      expect(described_class.search("sagrada familia")).to eq([ church ])
      expect(described_class.search("  ")).to be_empty
    end

    it "ranks the closer match first, then the more prominent place" do
      small = landmark("Plaça Reial", prominence: 10)
      big = landmark("Plaça de Catalunya", prominence: 50)

      expect(described_class.search("placa reial").first).to eq(small)
      expect(described_class.search("placa").to_a).to eq([ big, small ])
    end

    it "leaves out unnamed landmarks" do
      destination.landmarks.create!(osm_type: "way", osm_id: 1, kind: "beach", geom: point_at)

      expect(described_class.search("beach")).to be_empty
    end
  end

  it "normalizes text to lowercase ASCII words" do
    expect(described_class.normalize("  Sagrada Família, Barcelona! ")).to eq("sagrada familia barcelona")
  end
end
