require "rails_helper"

RSpec.describe "Pagination" do
  let(:destination) { create(:destination) }

  before do
    21.times { |i| create(:property, :direct, destination:, name: format("Hotel %02d", i), distance_to_water_m: i + 1) }
  end

  it "shows 20 properties per page with a page navigation keeping the filters" do
    get destination_path(destination, kind: "hotel")

    document = Nokogiri::HTML(response.body)
    expect(document.css(".property-card").size).to eq(20)
    expect(response.body).to include("21 measured stays")
    nav_link = document.at_css("nav.pagy a[href*='page=2']")
    expect(nav_link["href"]).to include("kind=hotel")

    get destination_path(destination, kind: "hotel", page: 2)

    names = Nokogiri::HTML(response.body).css(".property-card__name").map { |n| n.text.strip }
    expect(names).to eq([ "Hotel 20" ])
  end

  it "sends pages beyond the last one to the last page, keeping the filters" do
    get destination_path(destination, kind: "hotel", page: 9)

    expect(response).to redirect_to(destination_path(destination, kind: "hotel", page: 2))
  end

  it "pages the admin list by 50" do
    sign_in_admin
    get admin_properties_path(view: "all")

    expect(response.body).to include("21 properties")
    expect(Nokogiri::HTML(response.body).css(".admin-table tbody tr").size).to eq(21)
  end
end
