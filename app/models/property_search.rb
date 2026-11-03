# Published properties of a destination, filtered and ordered for the
# listing page. With a stay and known prices the cheapest come first;
# otherwise the best waterfront position does.
class PropertySearch
  SORTS = %w[price waterfront].freeze
  SURFACES = %w[sand pebble rock].freeze
  PARAMS = %i[category surface kind sort].freeze

  attr_reader :destination, :stay, :category, :surface, :kind

  def initialize(destination:, stay: nil, params: {})
    @destination = destination
    @stay = stay if stay&.valid?
    @category = params[:category].presence_in(Verifications::Waterfront::LISTED_CATEGORIES)
    @surface = params[:surface].presence_in(SURFACES)
    @kind = params[:kind].presence_in(Property::KINDS)
    @sort = params[:sort].presence_in(SORTS)
  end

  def sort
    @sort || (stay ? "price" : "waterfront")
  end

  # Matching properties, unordered.
  def filtered
    scope = destination.properties.published.left_joins(:waterfront)
    scope = scope.where(verifications: { category: }) if category
    scope = scope.where("verifications.evidence->>'beach_surface' = ?", surface) if surface
    scope = scope.where(kind:) if kind
    scope
  end

  def results
    scope = filtered.preload(:destination, :active_listings, :waterfront)
    return scope.by_waterfront unless stay

    scope = scope.select("properties.*", "(#{best_price_sql}) AS best_price_cents")
    scope = scope.order(Arel.sql("best_price_cents ASC NULLS LAST")) if sort == "price"
    scope.by_waterfront
  end

  def filter_params
    { category:, surface:, kind:, sort: @sort }.compact
  end

  private

  def best_price_sql
    PriceQuote.fresh.for_stay(stay).joins(:listing)
      .where(currency: "EUR", listings: { active: true })
      .where("listings.property_id = properties.id")
      .select("MIN(price_quotes.total_cents)").to_sql
  end
end
