require "rails_helper"

RSpec.describe Search::Locator do
  let(:places) { JSON.parse(file_fixture("nominatim/eiffel.json").read).map { |json| Osm::Nominatim::Place.from_json(json) } }
  let(:nominatim) { instance_double(Osm::Nominatim, search: places) }
  let(:locator) { described_class.new(nominatim:) }

  def place(**changes)
    places.first.with(**changes)
  end

  it "saves the place as a searched landmark with its names and outline, in a new destination for its town" do
    result = locator.call([ "Eiffel Tower, Paris" ])

    expect(result.status).to eq(:found)
    landmark = result.landmark
    expect(landmark).to have_attributes(osm_type: "way", osm_id: 5_013_364, source: "search", kind: "attraction",
                                        name: "Eiffel Tower", local_name: "Tour Eiffel", slug: "eiffel-tower",
                                        prominence: 62, measured_at: nil)
    expect(landmark.names).to include("hu" => "Eiffel-torony", "alt_name" => "La Dame de fer")
    expect(landmark.geom.geometry_type).to eq(RGeo::Feature::Polygon)
    expect(Landmark.search("eiffel torony")).to include(landmark)

    destination = landmark.destination
    expect(destination).to have_attributes(name: "Paris", country_code: "FR", on_demand: true, published: true)
    south, west, north, east = landmark.walk_area
    expect(destination.bbox).to eq([ south, west, north, east ])
  end

  it "finds a place it saved before, and grows the town's destination for new ones" do
    first = locator.call([ "eiffel" ]).landmark
    expect(locator.call([ "eiffel" ]).landmark).to eq(first)

    allow(nominatim).to receive(:search).and_return([ place(osm_id: 1, lat: 43.33, names: { "name" => "Louvre" }, geojson: nil) ])
    louvre = locator.call([ "louvre" ]).landmark

    expect(louvre.destination).to eq(first.destination)
    expect(louvre.geom.geometry_type).to eq(RGeo::Feature::Point)
    expect(first.destination.reload.north).to be > first.walk_area[2]
  end

  it "puts a place inside a destination into it" do
    makarska = create(:destination)

    expect(locator.call([ "eiffel" ]).landmark.destination).to eq(makarska)
    expect(makarska.reload.bbox).to eq([ 43.25, 16.95, 43.35, 17.10 ])
  end

  it "tells a town from a place to stay near, and says when nothing or no one answers" do
    allow(nominatim).to receive(:search).and_return([ places.last ])
    expect(locator.call([ "paris" ])).to have_attributes(status: :too_big, place: "Paris")

    allow(nominatim).to receive(:search).and_return([])
    expect(locator.call([ "atlantis", "atlantis, ocean" ]).status).to eq(:not_found)
    expect(nominatim).to have_received(:search).with("atlantis, ocean")

    allow(nominatim).to receive(:search).and_return(nil)
    expect(locator.call([ "eiffel" ]).status).to eq(:unavailable)
  end

  it "names the kind of place from its OSM category" do
    kinds = { %w[tourism museum] => "museum", %w[highway pedestrian] => "pedestrian_street", %w[natural beach] => "beach",
              %w[railway station] => "station", %w[building house] => "place" }
    kinds.each_with_index do |((category, type), kind), index|
      allow(nominatim).to receive(:search).and_return([ place(osm_id: 100 + index, category:, type:, geojson: nil) ])

      expect(locator.call([ "x" ]).landmark.kind).to eq(kind)
    end
  end
end
