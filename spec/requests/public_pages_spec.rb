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
    it "lists published destinations with verified counts" do
      create(:destination, name: "Hidden Coast", published: false)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Makarska Riviera", "1 verified stay", "1 right on the beach")
      expect(response.body).not_to include("Hidden Coast")
    end

    it "gives the destination options what the searchable list shows" do
      get root_path

      document = Nokogiri::HTML(response.body)
      option = document.at_css("select#destination option[value='#{destination.slug}']")
      expect(option.parent["label"]).to eq("Croatia")
      expect(option.to_h).to include("data-sea" => "Adriatic Sea", "data-count" => "1")
      expect(document.at_css("select#destination")["required"]).to be_present
      labels = JSON.parse(document.at_css("form[data-search-form]")["data-search-form"])
      expect(labels).to include("where_to" => "Where are you going?", "stays" => hash_including("one" => "1 verified stay"))
    end

    it "sends the search form to the destination with the stay" do
      get search_path(destination: destination.slug, **stay_params)

      expect(response).to redirect_to(destination_path(destination, stay_params))
    end

    it "shows a notice instead of an unusable search form without destinations" do
      Destination.update_all(published: false)

      get root_path

      expect(response.body).to include("still measuring our first coastline")
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
      get destination_path(destination, stay_params.merge(surface: "pebble"))

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

    it "shows the official website instead of a price form when no booking site lists it" do
      hotel.update!(website: "https://hotel-riva.example")

      get property_path(hotel)

      panel = Nokogiri::HTML(response.body).at_css(".booking-panel")
      expect(panel.text).to include("Not bookable through our partners yet", "More verified stays in Makarska Riviera")
      expect(panel.at_css("a[href='https://hotel-riva.example']")["rel"]).to eq("nofollow noopener")
      expect(panel.at_css("form")).to be_nil
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

      get sitemap_path

      expect(response.media_type).to eq("application/xml")
      expect(response.body).to include(destination_url(destination), property_url(hotel))
      expect(response.body.scan("<url>").size).to eq(4)
    end

    it "points robots to the sitemap and away from redirects" do
      get "/robots.txt"

      expect(response.body).to include("Disallow: /go/", "Sitemap: #{sitemap_url}")
    end
  end
end
