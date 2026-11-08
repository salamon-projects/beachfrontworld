# Structured data (schema.org JSON-LD) and social sharing tags. JSON-LD is a
# data block, not a script the browser runs, so the CSP does not block it.
module SeoHelper
  LODGING_TYPES = { "hotel" => "Hotel", "resort" => "Resort", "motel" => "Motel", "hostel" => "Hostel",
                    "guest_house" => "BedAndBreakfast", "camp_site" => "Campground" }.freeze

  # to_json escapes <, > and & so the data cannot close the tag.
  def json_ld(data)
    tag.script(data.to_json.html_safe, type: "application/ld+json") # rubocop:disable Rails/OutputSafety
  end

  def og_image_url
    "#{request.base_url}/og-image.jpg"
  end

  def website_ld
    { "@context" => "https://schema.org", "@type" => "WebSite", "name" => t("site_name"), "url" => root_url,
      "description" => t("tagline"),
      "publisher" => { "@type" => "Organization", "name" => t("site_name"), "url" => root_url,
                       "logo" => "#{request.base_url}/icon.png" } }
  end

  # items: [name, url] pairs, from the home page down.
  def breadcrumb_ld(items)
    { "@context" => "https://schema.org", "@type" => "BreadcrumbList",
      "itemListElement" => items.each_with_index.map do |(name, url), index|
        { "@type" => "ListItem", "position" => index + 1, "name" => name, "item" => url }
      end }
  end

  def destination_ld(destination, properties, offset: 0)
    { "@context" => "https://schema.org", "@type" => "ItemList",
      "name" => "Beachfront stays in #{destination.name}",
      "itemListElement" => properties.each_with_index.map do |property, index|
        { "@type" => "ListItem", "position" => offset + index + 1, "url" => property_url(property),
          "name" => property.name }
      end }
  end

  def lodging_ld(property)
    destination = property.destination
    data = { "@context" => "https://schema.org", "@type" => LODGING_TYPES.fetch(property.kind, "LodgingBusiness"),
             "name" => property.name, "url" => property_url(property),
             "description" => [ measured_distance(property), "#{t("properties.kinds.#{property.kind}")} in #{destination.name}, #{destination.country_name}" ].compact.join(". "),
             "geo" => { "@type" => "GeoCoordinates", "latitude" => property.latitude.round(6), "longitude" => property.longitude.round(6) },
             "address" => { "@type" => "PostalAddress", "streetAddress" => property.address.presence,
                            "addressLocality" => destination.name, "addressCountry" => destination.country_code }.compact }
    data["starRating"] = { "@type" => "Rating", "ratingValue" => property.stars } if property.stars
    data["sameAs"] = property.website if property.website_link?
    data
  end
end
