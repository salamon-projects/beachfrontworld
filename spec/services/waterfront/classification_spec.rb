require "rails_helper"

RSpec.describe Waterfront::Classification do
  let(:destination) { create(:destination) }
  let(:property) { create(:property, destination:) }

  # Returns the stored waterfront result.
  def classify(record = property)
    described_class.new(record.reload).call.reload.waterfront
  end

  it "classifies a property 20 m from the sea as direct" do
    create(:water_feature, geom: east_west_line(north_m: 20))

    result = classify
    expect(result).to have_attributes(category: "direct", water_kind: "sea", crosses_road: false)
    expect(result.distance_m).to be_within(1).of(20)
    expect(result.water_point.last).to be > property.lonlat.y
    expect(result.measured_at).to be_present
  end

  it "downgrades to near when a road lies between" do
    create(:water_feature, geom: east_west_line(north_m: 40))
    create(:road_segment, geom: east_west_line(north_m: 20))

    expect(classify).to have_attributes(category: "near", crosses_road: true)
  end

  it "ignores a road behind the property" do
    create(:water_feature, geom: east_west_line(north_m: 40))
    create(:road_segment, geom: east_west_line(north_m: -20))

    expect(classify).to have_attributes(category: "direct", crosses_road: false)
  end

  it "notes a promenade without downgrading" do
    create(:water_feature, geom: east_west_line(north_m: 40))
    create(:road_segment, category: "promenade", highway: "footway", geom: east_west_line(north_m: 20))

    expect(classify).to have_attributes(category: "direct", crosses_promenade: true)
  end

  it "treats a property on a wide sandy beach as direct" do
    create(:water_feature, geom: east_west_line(north_m: 120))
    create(:beach, geom: box(south_m: 10, north_m: 120))

    result = classify
    expect(result).to have_attributes(category: "direct", beach_surface: "sand")
    expect(result.distance_to_beach_m).to be_within(1).of(10)
  end

  it "classifies 250 m as walkable" do
    create(:water_feature, geom: east_west_line(north_m: 250))

    expect(classify.category).to eq("walkable")
  end

  it "excludes a property 700 m away even when a booking site calls it beachfront" do
    create(:water_feature, geom: east_west_line(north_m: 700))
    create(:listing, property:, claims_beachfront: true)

    expect(classify.category).to eq("not_waterfront")
    expect(Property.published).not_to include(property)
    expect(Property.beachfront_claim_conflicts).to include(property)
  end

  it "is unknown until water has been imported for the destination" do
    expect(classify.category).to eq("unknown")
  end

  it "updates the existing result instead of adding another" do
    create(:water_feature, geom: east_west_line(north_m: 20))
    classify
    classify

    expect(Verification.where(property:).count).to eq(1)
  end

  it "measures from the footprint edge rather than the centre" do
    create(:water_feature, geom: east_west_line(north_m: 60))
    with_footprint = create(:property, destination:, footprint: box(south_m: -30, north_m: 30, west_m: -20, east_m: 20))

    result = classify(with_footprint)
    expect(result.distance_m).to be_within(1).of(30)
    expect(result.category).to eq("direct")
  end

  it "records how far a booking site's position is from ours" do
    create(:water_feature, geom: east_west_line(north_m: 20))
    lon, lat = offset(north_m: 300)
    create(:listing, property:, reported_latitude: lat, reported_longitude: lon)

    classify
    expect(property.reload.coord_mismatch_m).to be_within(1).of(300)
    expect(property).to be_coordinate_mismatch
  end
end
