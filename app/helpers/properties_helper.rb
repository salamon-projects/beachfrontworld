module PropertiesHelper
  def waterfront_badge(property, large: false)
    category = waterfront_category(property)
    tag.span(t("waterfront.categories.#{category}"),
             class: [ "badge", "badge--#{category}", ("badge--large" if large) ],
             title: waterfront_hint(category))
  end

  def waterfront_category(property)
    property.waterfront&.category || "unknown"
  end

  def waterfront_hint(category)
    config = Waterfront.config
    t("waterfront.category_hints.#{category}",
      near: config.fetch(:near_max_m), walkable: config.fetch(:walkable_max_m), default: nil)
  end

  def measured_distance(property)
    waterfront = property.waterfront
    return if waterfront&.distance_m.nil?

    if waterfront.distance_m.zero?
      t("waterfront.on_the_water", water: waterfront.water_display_name)
    else
      t("waterfront.measured", distance: number_with_delimiter(waterfront.distance_m), water: waterfront.water_display_name)
    end
  end

  # The measured distance split for display: ["18 m", "to the Adriatic Sea"].
  def distance_parts(property)
    waterfront = property.waterfront
    return if waterfront&.distance_m.nil?

    water = waterfront.water_display_name
    caption = waterfront.distance_m.zero? ? t("waterfront.right_on", water:) : t("waterfront.to_water", water:)
    [ "#{number_with_delimiter(waterfront.distance_m)} m", caption ]
  end

  # Positions on the distance ruler (shared/_distance_ruler): SVG x for a
  # distance, on a scale up to the walkable limit.
  def ruler_x(metres, max)
    12 + (metres.to_f.clamp(0, max) / max * 292).round(1)
  end

  # The booking site's official logo once one is configured (see
  # config/affiliates.yml), otherwise its name.
  def provider_mark(listing)
    config = listing.provider_config
    if config&.logo
      image_tag(config.logo, alt: listing.provider_name, class: "provider-mark provider-mark--logo")
    else
      tag.span(listing.provider_name, class: "provider-mark")
    end
  end

  # How much the best price saves against the highest one, when that is
  # worth mentioning.
  def offers_saving(offers)
    totals = offers.filter_map { |offer| offer.quote&.total_cents }
    return if totals.size < 2

    saving = totals.max - totals.min
    saving if saving >= 100
  end

  def property_kind(property)
    label = t("properties.kinds.#{property.kind}")
    property.stars ? "#{label} · #{'★' * property.stars}" : label
  end

  def beach_surface_label(property)
    surface = property.waterfront&.beach_surface
    t("waterfront.beach_surfaces.#{surface}") if surface.present?
  end

  # Notes shown under the badge: what lies between the property and the water.
  def waterfront_notes(property)
    waterfront = property.waterfront
    return [] unless waterfront

    notes = []
    notes << [ :warning, t("waterfront.road_between") ] if waterfront.crosses_road?
    notes << [ :info, t("waterfront.promenade_between") ] if waterfront.crosses_promenade?
    notes << [ :info, beach_surface_label(property) ] if waterfront.beach_surface.present?
    notes
  end

  def property_map_data(property)
    data = { properties: [ map_point(property) ], maxZoom: 18 }
    data[:footprint] = property.footprint.exterior_ring.points.map { |p| [ p.y, p.x ] } if property.footprint
    water_lon, water_lat = property.waterfront&.water_point
    if water_lon && water_lat
      from_lon, from_lat = property.footprint ? closest_footprint_vertex(property, water_lon, water_lat) : [ property.lonlat.x, property.lonlat.y ]
      data[:measurement] = {
        from: [ from_lat, from_lon ], to: [ water_lat, water_lon ],
        label: t("waterfront.measured_short", distance: property.waterfront.distance_m)
      }
    end
    data
  end

  # One line describing the current search, shown when the filters are folded.
  def filters_summary(search, stay)
    parts = []
    parts << (stay ? "#{l(stay.check_in, format: '%-d %b')} – #{l(stay.check_out, format: '%-d %b')}" : t("search.any_dates"))
    parts << pluralize(stay.adults, "adult") if stay
    parts << pluralize(stay.children, "child") if stay&.children&.positive?
    active = [ search.category, search.surface, search.kind ].compact.size
    parts << pluralize(active, "filter") if active.positive?
    parts << t("search.sorts.#{search.sort}")
    parts.join(" · ")
  end

  def destination_map_data(destination, points)
    { center: [ destination.center.y, destination.center.x ], zoom: destination.zoom, maxZoom: 16, properties: points }
  end

  def map_point(property, url: nil)
    { lat: property.lonlat.y, lon: property.lonlat.x, name: property.name, category: waterfront_category(property), url: }
  end

  private

  # The footprint vertex nearest the water point as [lon, lat]; close enough
  # to draw the measurement line from the building edge.
  def closest_footprint_vertex(property, water_lon, water_lat)
    vertex = property.footprint.exterior_ring.points.min_by { |p| (p.x - water_lon)**2 + (p.y - water_lat)**2 }
    [ vertex.x, vertex.y ]
  end
end
