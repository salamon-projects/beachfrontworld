require "rails_helper"

RSpec.describe PropertySearch do
  let(:destination) { create(:destination) }
  let(:stay) { Stay.new(check_in: Date.current + 20, check_out: Date.current + 23, adults: 2) }
  let!(:direct) { create(:property, :direct, destination:, beach_surface: "pebble") }
  let!(:near) { create(:property, :near, destination:, beach_surface: "sand") }
  let!(:walkable) { create(:property, :walkable, destination:, kind: "apartment") }

  before do
    create(:property, :direct, :hidden, destination:)
    create(:property, :direct) # other destination
  end

  def price(property, cents)
    create(:price_quote, listing: create(:listing, property:), total_cents: cents, **stay.to_params)
  end

  it "orders by waterfront position without a stay" do
    expect(described_class.new(destination:).results.to_a).to eq([ direct, near, walkable ])
  end

  it "orders by the cheapest fresh price with a stay, unpriced last" do
    price(walkable, 20_000)
    price(near, 30_000)

    search = described_class.new(destination:, stay:)
    expect(search.sort).to eq("price")
    expect(search.results.to_a).to eq([ walkable, near, direct ])
    expect(search.results.first.best_price_cents).to eq(20_000)
  end

  it "can sort by waterfront position even with a stay" do
    price(walkable, 20_000)

    results = described_class.new(destination:, stay:, params: { sort: "waterfront" }).results
    expect(results.to_a).to eq([ direct, near, walkable ])
  end

  it "filters by category, beach surface and kind, ignoring unknown values" do
    expect(described_class.new(destination:, params: { category: "near" }).results).to eq([ near ])
    expect(described_class.new(destination:, params: { surface: "pebble" }).results).to eq([ direct ])
    expect(described_class.new(destination:, params: { kind: "apartment" }).results).to eq([ walkable ])
    expect(described_class.new(destination:, params: { category: "not_waterfront" }).results.size).to eq(3)
  end
end
