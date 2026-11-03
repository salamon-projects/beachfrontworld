require "rails_helper"

RSpec.describe "Public pages" do
  let(:destination) { create(:destination, name: "Makarska Riviera", sea_name: "Adriatic Sea") }
  let!(:hotel) do
    create(:property, :direct, destination:, name: "Hotel Riva", stars: 4, distance_to_water_m: 18,
                                         beach_surface: "pebble", crosses_promenade: true)
  end
  let(:check_in) { Date.current + 30 }
  let(:stay_params) { { check_in: check_in.iso8601, check_out: (check_in + 3).iso8601, adults: 2 } }

  describe "home" do
    it "lists published destinations with their counts, and their best-known landmarks to try" do
      create(:destination, name: "Hidden Coast", published: false)
      gate = create(:landmark, destination:, name: "Old Town Gate", prominence: 40)
      create(:landmark, destination:, kind: "beach", name: nil)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Makarska Riviera", "1 measured stay", "1 place to stay near")
      expect(response.body).not_to include("Hidden Coast")
      expect(Nokogiri::HTML(response.body).at_css(".hero__examples a")["href"]).to eq(landmark_path(gate))
    end

    it "sends the search form to the destination with the stay" do
      get search_path(destination: destination.slug, **stay_params)

      expect(response).to redirect_to(destination_path(destination, stay_params))
    end

    it "shows a notice instead of an unusable search form without destinations" do
      Destination.update_all(published: false)

      get root_path

      expect(response.body).to include("still measuring our first destination")
      expect(Nokogiri::HTML(response.body).at_css("form.search-form")).to be_nil
    end

    it "offers a skip link to the main content" do
      get root_path

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("a.skip-link")["href"]).to eq("#main")
      expect(document.at_css("main#main")).to be_present
    end

    it "asks for a destination when none is chosen" do
      get search_path(destination: "")

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "destination" do
    it "shows only published properties with their measurement" do
      create(:property, :direct, :hidden, destination:, name: "Hidden Hotel")
      create(:property, :not_waterfront, destination:, name: "Inland Hotel")

      get destination_path(destination)

      expect(response.body).to include("Hotel Riva", "Verified beachfront", "Pebble beach", "A promenade or path runs in front")
      expect(Nokogiri::HTML(response.body).at_css(".waterfront-summary__distance").text.squish)
        .to eq("Measured 18 m to the Adriatic Sea")
      expect(response.body).not_to include("Hidden Hotel", "Inland Hotel")
      expect(response.body).to include("data-map=")
    end

    it "links offers through the outbound redirect, marked sponsored" do
      listing = create(:listing, property: hotel)

      get destination_path(destination)

      document = Nokogiri::HTML(response.body)
      link = document.at_css("a.offer__link")
      expect(link["href"]).to eq(outbound_path(listing))
      expect(link["rel"]).to include("sponsored")
    end

    it "orders by price when dates are given and prices are known" do
      cheap = create(:property, :walkable, destination:, name: "Budget Rooms")
      create(:listing, property: hotel)
      create(:listing, property: cheap)
      Rails.configuration.x.price_providers = %w[fake]
      allow_any_instance_of(Prices::Providers::Fake).to receive(:quotes_for) do |_, listings, _|
        listings.map { |l| Prices::Quote.new(listing_id: l.id, total_cents: l.property_id == cheap.id ? 20_000 : 50_000, currency: "EUR") }
      end

      get destination_path(destination, stay_params)

      names = Nokogiri::HTML(response.body).css(".property-card__name").map(&:text)
      expect(names).to eq([ "Budget Rooms", "Hotel Riva" ])
      expect(response.body).to include("€200", "Best price", "noindex")
      expect(response.body).to include(outbound_path(Listing.find_by(property: cheap), stay_params).gsub("&", "&amp;"))
    ensure
      Rails.configuration.x.price_providers = []
    end

    it "folds the filters and summarises the current search" do
      get destination_path(destination, stay_params.merge(kind: "hotel"))

      filters = Nokogiri::HTML(response.body).at_css("details.filters")
      expect(filters["open"]).to be_nil
      expect(filters.at_css(".filters__current").text).to eq(
        "#{check_in.strftime('%-d %b')} – #{(check_in + 3).strftime('%-d %b')} · 2 adults · 1 filter · Lowest price"
      )
    end

    it "counts children in the summary and keeps their ages in the form" do
      get destination_path(destination, stay_params.merge(children: 2, child_ages: [ 4, 9 ]))

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".filters__current").text).to include("2 adults · 2 children")
      expect(page.at_css("#child_age_1 option[selected]")["value"]).to eq("4")
      expect(page.at_css("#child_age_2 option[selected]")["value"]).to eq("9")
    end

    it "keeps the filters open when the dates need correcting" do
      get destination_path(destination, check_in: check_in.iso8601, check_out: (check_in - 1).iso8601)

      expect(Nokogiri::HTML(response.body).at_css("details.filters")["open"]).not_to be_nil
    end

    it "shows a validation message for impossible dates" do
      get destination_path(destination, check_in: check_in.iso8601, check_out: (check_in - 1).iso8601)

      expect(response.body).to include("Check out must be after check-in")
    end

    it "returns 404 for unpublished destinations" do
      destination.update!(published: false)

      get destination_path(destination)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "search and landmark pages" do
    let!(:gate) { create(:landmark, destination:, name: "Old Town Gate", kind: "historic") }
    let!(:beach) { create(:landmark, destination:, name: nil, kind: "beach") }

    before do
      hotel.walks.create!(landmark: gate, walk_m: 640, busy_crossings: 1, stairs: 2, measured_at: Time.current)
      hotel.walks.create!(landmark: beach, walk_m: 30, measured_at: Time.current)
    end

    it "sends a typed place to its landmark page, keeping the stay" do
      get search_path(q: "old town gate", **stay_params)

      expect(response).to redirect_to(landmark_path(gate, stay_params))
    end

    it "shows stays near a landmark with the measured walk" do
      get landmark_path(gate)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("h1").text.squish).to eq("Stays near Old Town Gate")
      expect(page.at_css(".walk-summary .waterfront-summary__distance").text.squish)
        .to eq("Measured walk 8 min to Old Town Gate · 850 steps")
      expect(response.body).to include("Crosses 1 busy road on the way", "2 flights of steps on the way")
      expect(JSON.parse(page.at_css("[data-map]")["data-map"])["landmarks"].first["name"]).to eq("Old Town Gate")
      expect(page.at_css(".property-card__name a")["href"]).to eq(property_path(hotel, near: gate.slug))
    end

    it "lists stays near the nearest landmark of a kind" do
      get destination_path(destination, near: "beach")

      expect(response.body).to include("Measured walk", "to a beach", "No busy road to cross on the way")
      expect(Nokogiri::HTML(response.body).css(".landmark-chip").map(&:text)).to eq([ "Old Town Gate" ])
    end

    it "shows the choices, or the destinations when nothing matches" do
      create(:landmark, destination:, name: "Old Town Hall")

      get search_path(q: "old town")
      expect(response.body).to include("Which one did you mean?", "Old Town Gate", "Old Town Hall")

      get search_path(q: "Atlantis")
      expect(response.body).to include("could not find that place", "Makarska Riviera")
    end

    it "leads the property page with the walk to the landmark searched near" do
      get property_path(hotel, near: gate.slug)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".property-layout__summary .waterfront-summary__distance").text.squish)
        .to eq("Measured walk 8 min to Old Town Gate · 850 steps")
      expect(page.at_css(".walk-list").text.squish).to include("A beach", "1 min")
      expect(page.at_css(".property-waterfront").text).to include("Verified beachfront")
      map = JSON.parse(page.at_css("[data-map]")["data-map"])
      expect(map["landmarks"].first["name"]).to eq("Old Town Gate")
      expect(page.at_css("title").text).to start_with("Hotel Riva, Makarska Riviera — 8 min walk to Old Town Gate")
      expect(response.body).to include("noindex")

      get property_path(hotel)
      expect(Nokogiri::HTML(response.body).at_css(".property-layout__summary").text).to include("to Old Town Gate")
    end

    it "asks for a place when the search is empty" do
      get search_path(q: " ")

      expect(response).to redirect_to(root_path)
    end

    it "returns 404 for unnamed landmarks and unpublished destinations" do
      get landmark_path(beach)
      expect(response).to have_http_status(:not_found)

      destination.update!(published: false)
      get landmark_path(gate)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "property" do
    it "shows the checks and the map" do
      get property_path(hotel)

      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".map")["role"]).to eq("region")
      sections = document.css(".property-layout > *").map { |node| node["class"] }
      expect(sections).to eq(%w[property-layout__summary property-layout__booking property-layout__details])

      expect(response.body).to include("Hotel Riva", "What we checked", "No road or railway between", "data-map=")
      expect(Nokogiri::HTML(response.body).at_css("link[rel=canonical]")["href"]).to eq(property_url(hotel))
    end

    it "warns about a road between the property and the water" do
      hotel.waterfront.update!(crosses_road: true, category: "near")

      get property_path(hotel)

      expect(response.body).to include("A road or railway runs between the property and the water")
    end

    it "returns 404 for hidden properties" do
      hotel.update!(hidden_at: Time.current)

      get property_path(hotel)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "static pages" do
    it "explains the method with the configured thresholds" do
      get how_we_verify_path

      expect(response.body).to include("How results are ordered", "at most #{Waterfront.config.fetch(:direct_max_m)} m away")
    end

    it "renders the disclosure and privacy pages" do
      get affiliate_disclosure_path
      expect(response).to have_http_status(:ok)

      get privacy_path
      expect(response.body).to include("IP address")
    end

    it "lists published pages in the sitemap" do
      create(:property, :direct, :hidden, destination:, name: "Hidden Hotel")
      gate = create(:landmark, destination:, name: "Old Town Gate")
      hotel.walks.create!(landmark: gate, walk_m: 300, measured_at: Time.current)
      create(:landmark, destination:, name: "Lonely Rock")

      get sitemap_path

      expect(response.media_type).to eq("application/xml")
      expect(response.body).to include(destination_url(destination), property_url(hotel), landmark_url(gate))
      expect(response.body).not_to include("lonely-rock")
      expect(response.body.scan("<url>").size).to eq(5)
    end

    it "points robots to the sitemap and away from redirects" do
      get "/robots.txt"

      expect(response.body).to include("Disallow: /go/", "Sitemap: #{sitemap_url}")
    end
  end
end
