# Published properties of a destination, or near a landmark whichever
# destination they belong to, filtered and ordered for the listing pages. With a target (one landmark, or the nearest landmark of a
# kind, such as the closest beach) properties are ordered by the walk to it;
# without one, by how many landmarks are within a short walk. With a stay
# and known prices the cheapest come first.
class PropertySearch
  SORTS = %w[price walk].freeze
  MINUTES = [ 5, 10, 15, 20, 30 ].freeze
  PARAMS = %i[near max_minutes kind quiet sort].freeze
  # "Lots to see on foot": landmarks within this walk count for the order
  # without a target.
  NEARBY_MINUTES = 15

  attr_reader :destination, :landmark, :stay, :near, :max_minutes, :kind

  def initialize(destination:, landmark: nil, stay: nil, params: {})
    @destination = destination
    @landmark = landmark
    @stay = stay if stay&.valid?
    @near = params[:near].presence_in(Landmark::KINDS) unless landmark
    @max_minutes = Integer(params[:max_minutes].to_s, exception: false).presence_in(MINUTES)
    @kind = params[:kind].presence_in(Property::KINDS)
    @quiet = params[:quiet].to_s == "1"
    @sort = params[:sort].presence_in(SORTS)
  end

  def sort
    @sort || (stay ? "price" : "walk")
  end

  # Walking to the target without crossing a primary, secondary or trunk road.
  def quiet?
    @quiet && target?
  end

  def target?
    landmark.present? || near.present?
  end

  # Matching properties, unordered. With a target each has near_walk_m,
  # near_busy_crossings, near_stairs and near_landmark_id; without one,
  # nearby_count.
  def filtered
    scope = (landmark ? Property : destination.properties).published
    scope = scope.where(kind:) if kind
    return scope.select("properties.*", "(#{nearby_count_sql}) AS nearby_count") unless target?

    scope = scope.joins(nearest_walk_sql)
                 .select("properties.*", "nearest.walk_m AS near_walk_m", "nearest.busy_crossings AS near_busy_crossings",
                         "nearest.stairs AS near_stairs", "nearest.landmark_id AS near_landmark_id")
    scope = scope.where(nearest: { walk_m: ..(max_minutes * Walks.config.fetch(:metres_per_minute)) }) if max_minutes
    scope = scope.where(nearest: { busy_crossings: 0 }) if quiet?
    scope
  end

  def results
    scope = filtered.preload(:destination, :active_listings, :waterfront)
    walk_order = target? ? "near_walk_m ASC" : "nearby_count DESC"
    if stay
      scope = scope.select("(#{best_price_sql}) AS best_price_cents")
      scope = scope.order(Arel.sql("best_price_cents ASC NULLS LAST")) if sort == "price"
    end
    scope.order(Arel.sql(walk_order), "properties.name", "properties.id")
  end

  def filter_params
    { near:, max_minutes:, kind:, quiet: ("1" if quiet?), sort: @sort }.compact
  end

  private

  # The property's shortest walk to the target.
  def nearest_walk_sql
    target = if landmark
      PropertyWalk.sanitize_sql_array([ "w.landmark_id = ?", landmark.id ])
    else
      PropertyWalk.sanitize_sql_array([ "l.destination_id = ? AND l.kind = ?", destination.id, near ])
    end
    <<~SQL.squish
      JOIN LATERAL (
        SELECT w.walk_m, w.busy_crossings, w.stairs, w.landmark_id
        FROM property_walks w JOIN landmarks l ON l.id = w.landmark_id
        WHERE w.property_id = properties.id AND #{target}
        ORDER BY w.walk_m LIMIT 1
      ) nearest ON true
    SQL
  end

  def nearby_count_sql
    PropertyWalk.sanitize_sql_array([ <<~SQL.squish, NEARBY_MINUTES * Walks.config.fetch(:metres_per_minute) ])
      SELECT COUNT(*) FROM property_walks w JOIN landmarks l ON l.id = w.landmark_id
      WHERE w.property_id = properties.id AND l.name IS NOT NULL AND w.walk_m <= ?
    SQL
  end

  def best_price_sql
    PriceQuote.fresh.for_stay(stay).joins(:listing)
      .where(currency: "EUR", listings: { active: true })
      .where("listings.property_id = properties.id")
      .select("MIN(price_quotes.total_cents)").to_sql
  end
end
