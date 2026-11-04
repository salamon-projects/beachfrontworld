require "rails_helper"

RSpec.describe Osm::Nominatim do
  let(:nominatim) { described_class.new(url: "https://nominatim.example", cache: ActiveSupport::Cache::NullStore.new) }
  let(:endpoint) { %r{\Ahttps://nominatim\.example/search\?} }

  it "asks for names, address and outline in English, as an identified client" do
    stub_request(:get, endpoint).to_return(body: file_fixture("nominatim/eiffel.json").read)

    places = nominatim.search("eiffel torony")

    expect(places.first).to have_attributes(osm_type: "way", osm_id: 5_013_364, category: "man_made", type: "tower",
                                            city: "Paris", country_code: "fr", lat: 43.3027, importance: 0.62)
    expect(places.first.names).to include("name:hu" => "Eiffel-torony")
    expect(WebMock).to have_requested(:get, endpoint).with(
      query: hash_including("q" => "eiffel torony", "format" => "jsonv2", "namedetails" => "1", "polygon_geojson" => "1",
                            "accept-language" => "en"),
      headers: { "User-Agent" => described_class::USER_AGENT }
    )
  end

  it "returns nil when Nominatim fails, and [] when nothing matches" do
    stub_request(:get, endpoint).to_return(status: 503).then.to_timeout.then.to_return(body: "[]")

    expect(nominatim.search("x")).to be_nil
    expect(nominatim.search("x")).to be_nil
    expect(nominatim.search("x")).to eq([])
  end

  it "asks at most once a second, waiting for the next second once" do
    cache = ActiveSupport::Cache::MemoryStore.new
    waits = []
    nominatim = described_class.new(url: "https://nominatim.example", cache:, sleeper: ->(seconds) { waits << seconds })
    stub_request(:get, endpoint).to_return(body: "[]")

    travel_to(Time.zone.local(2026, 11, 4, 12, 0, 0)) do
      expect(nominatim.search("one")).to eq([])
      expect(nominatim.search("two")).to be_nil
    end
    expect(waits.size).to eq(1)
    expect(WebMock).to have_requested(:get, endpoint).once
  end
end
