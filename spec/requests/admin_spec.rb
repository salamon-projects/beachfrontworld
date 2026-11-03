require "rails_helper"

RSpec.describe "Admin" do
  let(:destination) { create(:destination, name: "Makarska Riviera") }

  describe "signing in" do
    it "sends visitors to the login page and back to where they were going" do
      get admin_destinations_path
      expect(response).to redirect_to(admin_login_path)

      sign_in_admin
      expect(response).to redirect_to(admin_destinations_path)

      get admin_destinations_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Log out")
    end

    it "rejects a wrong password" do
      sign_in_admin(password: "wrong")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Wrong username or password.")
      get admin_properties_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "uses configured credentials, ignoring surrounding whitespace" do
      stub_const("ENV", ENV.to_h.merge("ADMIN_USER" => "editor\n", "ADMIN_PASSWORD" => " s3cret \n"))

      sign_in_admin
      expect(response).to have_http_status(:unprocessable_content)

      sign_in_admin(username: "editor", password: "s3cret")
      expect(response).to redirect_to(admin_root_path)
    end

    it "signs out" do
      sign_in_admin
      delete admin_logout_path

      expect(response).to redirect_to(admin_login_path)
      get admin_properties_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "expires the sign-in after twelve hours" do
      sign_in_admin

      travel 13.hours do
        get admin_properties_path
        expect(response).to redirect_to(admin_login_path)
      end
    end

    it "never redirects outside the admin after signing in" do
      get "/admin/properties"
      sign_in_admin
      expect(response).to redirect_to("/admin/properties")

      sign_in_admin
      expect(response).to redirect_to(admin_root_path)
    end
  end

  describe "properties" do
    before { sign_in_admin }

    let!(:candidate) { create(:property, :direct, destination:, name: "Hotel Candidate") }
    let!(:approved) { create(:property, :near, destination:, name: "Hotel Approved") }
    let!(:inland) { create(:property, :not_waterfront, destination:, name: "Hotel Inland") }

    it "shows the properties on the site by default, and those with nothing nearby apart" do
      get admin_properties_path

      expect(response.body).to include("Hotel Candidate", "Hotel Approved")
      expect(response.body).not_to include("Hotel Inland")

      get admin_properties_path(view: "unlisted")
      expect(response.body).to include("Hotel Inland", "nothing nearby")
      expect(response.body).not_to include("Hotel Candidate")
    end

    it "lists booking-site claims that contradict the measurement" do
      create(:listing, property: inland, claims_beachfront: true)

      get admin_properties_path(view: "conflicts")

      expect(response.body).to include("Hotel Inland", "OTA says beachfront")
      expect(response.body).not_to include("Hotel Candidate")
    end

    it "hides a property from the site and shows it again" do
      post hide_admin_property_path(candidate)

      expect(candidate.reload).to be_hidden.and be_reviewed
      expect(Property.published).not_to include(candidate)
      get admin_properties_path(view: "hidden")
      expect(response.body).to include("Hotel Candidate")

      post unhide_admin_property_path(candidate)
      expect(Property.published).to include(candidate)
    end

    it "steps through the list last opened, in its order" do
      get admin_properties_path(view: "all", destination_id: destination.id)

      get admin_property_path(approved)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".list-nav--top").text).to include("2 of 3 in", "All · Makarska Riviera")
      expect(page.at_css('.list-nav--top a[rel="prev"]')["href"]).to eq(admin_property_path(candidate))
      expect(page.at_css('.list-nav--top a[rel="next"]')["href"]).to eq(admin_property_path(inland))
      expect(page.at_css('.list-nav--bottom a[rel="next"]')["href"]).to eq(admin_property_path(inland))

      get admin_property_path(inland)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('.list-nav--top a[rel="next"]')).to be_nil
      expect(page.at_css('.list-nav--top [aria-disabled="true"]').text).to include("Next")
    end

    it "moves on from a property just hidden off the list" do
      get admin_properties_path

      post hide_admin_property_path(candidate)
      get admin_property_path(candidate)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".list-nav--top").text).to include("No longer in", "On the site")
      expect(page.at_css('.list-nav--top a[rel="next"]')["href"]).to eq(admin_property_path(approved))
    end

    it "lists and explains properties that OSM no longer has" do
      approved.update_columns(osm_type: "node", osm_id: 77, osm_missing_since: Time.zone.local(2026, 11, 2, 3))

      get admin_properties_path(view: "missing")
      expect(response.body).to include("Hotel Approved", "not in OSM")
      expect(response.body).not_to include("Hotel Candidate")

      get admin_property_path(approved)
      expect(response.body).to include("Not in OpenStreetMap any more.", "2 November 2026", "not listed on the site")
    end

    it "creates a property and measures it straight away" do
      create(:water_feature, geom: east_west_line(north_m: 30))
      lon, lat = offset

      post admin_properties_path, params: {
        property: { destination_id: destination.id, name: "Villa Manual", kind: "villa", latitude: lat, longitude: lon }
      }

      property = Property.find_by!(name: "Villa Manual")
      expect(response).to redirect_to(admin_property_path(property))
      expect(property.waterfront.category).to eq("direct")
      expect(property).to be_reviewed
      expect(property.waterfront.distance_m).to be_within(1).of(30)
    end

    it "re-measures after a coordinate correction" do
      create(:water_feature, geom: east_west_line(north_m: 30))
      lon, lat = offset(north_m: -400)

      patch admin_property_path(candidate), params: { property: { latitude: lat, longitude: lon } }

      expect(candidate.reload.waterfront.category).to eq("not_waterfront")
    end

    it "shows the measurement and listings" do
      create(:listing, property: candidate, claims_beachfront: true)

      get admin_property_path(candidate)

      expect(response.body).to include("Measurements", "Waterfront", "Booking.com", "data-map=")
    end

    it "shows the walks to landmarks in valid HTML" do
      landmark = create(:landmark, destination:, name: "Old Town Gate", kind: "historic")
      candidate.walks.create!(landmark:, walk_m: 640, busy_crossings: 1, measured_at: Time.current)

      get admin_property_path(candidate)

      expect(Nokogiri::HTML5(response.body, max_errors: 10).errors).to be_empty
      expect(response.body).to include("Old Town Gate", "640 m · 8 min")
    end

    it "re-renders the form on invalid input" do
      post admin_properties_path, params: { property: { destination_id: destination.id, name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("problem")
    end
  end

  describe "listings" do
    before { sign_in_admin }

    let(:property) { create(:property, :direct, destination:) }

    it "adds a listing and rejects foreign URLs" do
      post admin_property_listings_path(property), params: {
        listing: { provider: "agoda", url: "https://www.agoda.com/x/hotel/y.html", claims_beachfront: "true", active: "1" }
      }
      expect(property.listings.sole).to have_attributes(provider: "agoda", claims_beachfront: true)

      post admin_property_listings_path(property), params: {
        listing: { provider: "booking", url: "https://evil.example/hotel", active: "1" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("is not a Booking.com address")
    end

    it "flags a reported position far from ours" do
      lon, lat = offset(north_m: 400)

      perform_enqueued_jobs do
        post admin_property_listings_path(property), params: {
          listing: { provider: "booking", url: "https://www.booking.com/hotel/hr/x.html", reported_latitude: lat,
                     reported_longitude: lon, active: "1" }
        }
      end

      expect(property.reload.coord_mismatch_m).to be_within(1).of(400)
    end
  end

  describe "destinations" do
    before { sign_in_admin }

    it "creates a destination from a bounding box" do
      post admin_destinations_path, params: {
        destination: { name: "Zadar Riviera", country_code: "HR", sea_name: "Adriatic Sea",
                       south: "44.0", west: "15.1", north: "44.2", east: "15.4", zoom: "11", published: "1" }
      }

      expect(Destination.find_by!(slug: "zadar-riviera").bbox).to eq([ 44.0, 15.1, 44.2, 15.4 ])
    end

    it "accepts a lower-case country code" do
      post admin_destinations_path, params: {
        destination: { name: "Krk", country_code: " hr ", south: "45.0", west: "14.4", north: "45.2", east: "14.8" }
      }

      expect(Destination.find_by!(slug: "krk").country_code).to eq("HR")
    end

    it "queues an OSM import and shows its progress" do
      expect {
        post import_admin_destination_path(destination)
      }.to have_enqueued_job(OsmImportJob)

      run = destination.import_runs.sole
      expect(run).to be_queued
      run.start!(attempt: 1)
      run.progress!("roads", 3, 6)

      get admin_destinations_path
      expect(response.body).to include("Running", "Roads (step 4 of 6)", "refreshes every 10 seconds")
      expect(Nokogiri::HTML(response.body).at_css('meta[http-equiv="refresh"]')["content"]).to eq("10")
    end

    it "does not start a second import while one is running" do
      destination.import_runs.create!(status: "running")

      expect {
        post import_admin_destination_path(destination)
      }.not_to have_enqueued_job(OsmImportJob)
      expect(flash[:alert]).to include("already running")
    end

    it "lists finished and failed imports without refreshing" do
      destination.import_runs.create!(status: "succeeded", started_at: 3.minutes.ago, finished_at: Time.current,
                                      counts: { "accommodations" => 412, "coastline" => 9, "beaches" => 20, "roads" => 1500 })
      create(:destination, name: "Kassandra").import_runs.create!(status: "failed", finished_at: Time.current, error: "Overpass returned HTTP 504")

      get admin_imports_path

      expect(response.body).to include("Succeeded", "412 properties", "1,500 roads".delete(","), "Failed", "Overpass returned HTTP 504")
      expect(response.body).not_to include("removed", "no longer in OSM")
      expect(Nokogiri::HTML(response.body).at_css('meta[http-equiv="refresh"]')).to be_nil
    end

    it "reports map features removed and properties gone from OSM" do
      destination.import_runs.create!(status: "succeeded", started_at: 3.minutes.ago, finished_at: Time.current,
                                      counts: { "accommodations" => 10, "removed_features" => 4, "missing_from_osm" => 1 })

      get admin_destinations_path

      expect(response.body).to include("4 map features removed (gone from OSM)", "1 property no longer in OSM")
    end

    it "refuses to delete a destination that has properties" do
      create(:property, destination:)

      delete admin_destination_path(destination)

      expect(Destination.exists?(destination.id)).to be(true)
      expect(flash[:alert]).to be_present
    end
  end
end
