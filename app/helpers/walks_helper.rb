module WalksHelper
  # The walk PropertySearch found for a property in a targeted search, with
  # its landmark, as an (unsaved) PropertyWalk.
  def nearest_walk(property, landmarks)
    return unless property.has_attribute?(:near_walk_m)

    PropertyWalk.new(property:, landmark: landmarks[property.near_landmark_id], walk_m: property.near_walk_m,
                     busy_crossings: property.near_busy_crossings, stairs: property.near_stairs)
  end

  # "the Eiffel Tower", "Plaça Reial", "a beach".
  def landmark_label(landmark)
    landmark.name ? landmark.name : t("landmarks.unnamed.#{landmark.kind}")
  end

  # What lies on the way: busy roads to cross and flights of steps.
  def walk_notes(walk)
    notes = []
    notes << if walk.busy_crossings.zero?
      [ :info, t("walks.no_busy_roads") ]
    else
      [ :warning, t("walks.busy_roads", count: walk.busy_crossings) ]
    end
    notes << [ :info, t("walks.stairs", count: walk.stairs) ] if walk.stairs.positive?
    notes
  end

  def walk_steps(walk)
    t("walks.steps", steps: number_with_delimiter(walk.steps))
  end

  # Positions on the walk ruler (shared/_walk_ruler): SVG x for a number of
  # minutes, on a scale up to WALK_RULER_MAX.
  WALK_RULER_MAX = 20

  def walk_ruler_x(minutes)
    ruler_x(minutes, WALK_RULER_MAX)
  end

  # Kinds of landmark a destination has, for the "Close to" filter. Places
  # searched by address are not a kind anyone looks for.
  def near_kind_options(destination)
    kinds = destination.landmarks.distinct.pluck(:kind) - %w[place]
    Landmark::KINDS.select { |kind| kinds.include?(kind) }.map { |kind| [ t("search.near_kinds.#{kind}"), kind ] }
  end

  def sort_options(search)
    PropertySearch::SORTS.map do |sort|
      label = sort == "walk" && !search.target? ? t("search.sorts.most_nearby") : t("search.sorts.#{sort}")
      [ label, sort ]
    end
  end

  def ranking_note(search, stay)
    walk = search.target? ? t("search.ranking.walk") : t("search.ranking.nearby", minutes: PropertySearch::NEARBY_MINUTES)
    if stay && search.sort == "price"
      t("search.ranking.price", then: walk)
    else
      walk.upcase_first + "."
    end
  end

  # Tells the property page which landmark the visitor searched near.
  def walk_landmark_param(walk)
    walk&.landmark&.name ? { near: walk.landmark.slug } : {}
  end

  def landmark_map_point(landmark)
    lon, lat = landmark.position
    { lat:, lon:, name: landmark.display_name }
  end
end
