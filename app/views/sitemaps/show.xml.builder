xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  xml.url { xml.loc root_url }
  @destinations.each do |destination|
    xml.url do
      xml.loc destination_url(destination)
      xml.lastmod destination.updated_at.to_date.iso8601
    end
  end
  @properties.each do |property|
    xml.url do
      xml.loc property_url(property)
      xml.lastmod property.updated_at.to_date.iso8601
    end
  end
  xml.url { xml.loc how_we_verify_url }
end
