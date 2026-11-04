require "rails_helper"

RSpec.describe PropertySearch do
  let(:destination) { create(:destination) }
  let(:stay) { Stay.new(check_in: Date.current + 20, check_out: Date.current + 23, adults: 2) }
  let(:tower) { create(:landmark, destination:, name: "Old Tower") }
  let(:beach) { create(:landmark, destination:, kind: "beach", name: nil) }
  let(:other_beach) { create(:landmark, destination:, kind: "beach", name: "Long Beach") }
  let!(:close) { create(:property, destination:, name: "Close") }
  let!(:middle) { create(:property, destination:, name: "Middle", kind: "apartment") }
  let!(:far) { create(:property, destination:, name: "Far") }

  before do
    walk(close, tower, 200, busy_crossings: 1)
    walk(middle, tower, 700)
    walk(far, tower, 950)
    walk(far, beach, 100)
    walk(close, other_beach, 900)
    walk(create(:property, :hidden, destination:), tower, 50)
    walk(create(:property), create(:landmark), 50) # other destination
  end

  def walk(property, landmark, metres, busy_crossings: 0)
    property.walks.create!(landmark:, walk_m: metres, busy_crossings:, measured_at: Time.current)
  end

  def price(property, cents)
    create(:price_quote, listing: create(:listing, property:), total_cents: cents, **stay.to_params)
  end

  it "orders by the walk to a landmark, with the walk on each result" do
    results = described_class.new(destination:, landmark: tower).results.to_a

    expect(results).to eq([ close, middle, far ])
    expect(results.first).to have_attributes(near_walk_m: 200, near_busy_crossings: 1, near_landmark_id: tower.id)
  end

  it "orders by the walk to the nearest landmark of a kind" do
    results = described_class.new(destination:, params: { near: "beach" }).results.to_a

    expect(results).to eq([ far, close ])
    expect(results.map(&:near_landmark_id)).to eq([ beach.id, other_beach.id ])
  end

  it "filters by the longest walk, quiet walks and kind of property" do
    expect(described_class.new(destination:, landmark: tower, params: { max_minutes: "10" }).results).to eq([ close, middle ])
    expect(described_class.new(destination:, landmark: tower, params: { quiet: "1" }).results).to eq([ middle, far ])
    expect(described_class.new(destination:, landmark: tower, params: { kind: "apartment" }).results).to eq([ middle ])
    expect(described_class.new(destination:, landmark: tower, params: { max_minutes: "7", near: "nope" }).max_minutes).to be_nil
  end

  it "orders by how much is within a short walk without a target" do
    2.times { walk(middle, create(:landmark, destination:), 300) }

    expect(described_class.new(destination:).results.to_a).to eq([ middle, close, far ])
  end

  it "leaves out walks longer than the admin's limit" do
    SiteSetting.current.update!(max_walk_m: 800)

    only_far = create(:property, destination:)
    walk(only_far, tower, 950)

    expect(described_class.new(destination:, landmark: tower).results.to_a).to eq([ close, middle ])
    expect(Property.published).not_to include(only_far)
    expect(described_class.minute_options).to eq([ 5, 10 ])
  end

  it "orders by the cheapest fresh price with a stay, unpriced last" do
    price(far, 20_000)
    price(middle, 30_000)

    search = described_class.new(destination:, landmark: tower, stay:)
    expect(search.sort).to eq("price")
    expect(search.results.to_a).to eq([ far, middle, close ])
    expect(search.results.first.best_price_cents).to eq(20_000)
    expect(described_class.new(destination:, landmark: tower, stay:, params: { sort: "walk" }).results.to_a)
      .to eq([ close, middle, far ])
  end
end
