require "rails_helper"

RSpec.describe Websites::Checker do
  let(:addresses) { { "hotel.example" => [ "93.184.216.34" ], "www.hotel.example" => [ "93.184.216.34" ] } }
  let(:resolver) { Class.new { def initialize(map) = @map = map; def getaddresses(host) = @map.fetch(host, []) }.new(addresses) }
  let(:checker) { described_class.new(resolver:) }
  let(:property) { create(:property, :direct, website: "https://hotel.example/") }
  let(:page) { "<!doctype html><html><head><title>Hotel</title></head><body><h1>Welcome to the hotel</h1></body></html>" }

  it "keeps the link of a page that loads" do
    stub_request(:get, "https://hotel.example/").to_return(status: 200, body: page)

    expect(checker.record(property)).to be_ok
    expect(property.reload).to have_attributes(website_status: "HTTP 200", website_failures: 0, website_broken_at: nil)
    expect(property.website_checked_at).to be_present
    expect(property).to be_website_link
  end

  it "follows redirects" do
    stub_request(:get, "https://hotel.example/").to_return(status: 301, headers: { "Location" => "https://www.hotel.example/en" })
    stub_request(:get, "https://www.hotel.example/en").to_return(status: 200, body: page)

    expect(checker.check("https://hotel.example/")).to be_ok
  end

  it "hides an empty page, a missing page or a parked domain at once" do
    { "empty page" => { status: 200, body: "  \n" },
      "HTTP 404" => { status: 404, body: page },
      "parked domain" => { status: 200, body: "<html><body>This domain is for sale! Buy this domain today.</body></html>" } }
      .each do |status, response|
        stub_request(:get, "https://hotel.example/").to_return(**response)
        property.update_columns(website_broken_at: nil, website_failures: 0)

        checker.record(property)

        expect(property.reload.website_status).to eq(status)
        expect(property).not_to be_website_link
      end
  end

  it "hides a domain that no longer exists" do
    property.update!(website: "https://gone.example/")

    expect(checker.record(property).status).to eq("domain not found")
    expect(property.reload).not_to be_website_link
  end

  it "keeps the link of a site that refuses automated checks" do
    stub_request(:get, "https://hotel.example/").to_return(status: 403)

    checker.record(property)

    expect(property.reload).to be_website_link
    expect(property.website_status).to eq("HTTP 403 (refuses automated checks)")
  end

  it "hides a link only when a server error or timeout happens twice in a row" do
    stub_request(:get, "https://hotel.example/").to_return(status: 503).then.to_timeout

    checker.record(property)
    expect(property.reload).to have_attributes(website_failures: 1, website_status: "HTTP 503")
    expect(property).to be_website_link

    checker.record(property)
    expect(property.reload.website_status).to start_with("no response")
    expect(property).not_to be_website_link
  end

  it "shows the link again once the page loads" do
    property.update_columns(website_broken_at: 1.week.ago, website_failures: 2)
    stub_request(:get, "https://hotel.example/").to_return(status: 200, body: page)

    checker.record(property)

    expect(property.reload).to be_website_link
  end

  it "never connects to a private or local address" do
    addresses["intranet.example"] = [ "10.0.0.5" ]
    addresses["localhost.example"] = [ "127.0.0.1", "::1" ]

    expect(checker.check("http://intranet.example/").status).to eq("not a public address")
    expect(checker.check("http://localhost.example:3000/admin").status).to eq("not a public address")
    expect(WebMock).not_to have_requested(:get, /example/)
  end

  it "checks a changed address afresh" do
    property.update_columns(website_broken_at: 1.week.ago, website_failures: 2, website_status: "HTTP 404")

    property.update!(website: "https://www.hotel.example/")

    expect(property.reload).to have_attributes(website_broken_at: nil, website_failures: 0, website_status: nil)
  end
end
