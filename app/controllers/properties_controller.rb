class PropertiesController < ApplicationController
  # Walks listed under "Within walking distance".
  NEARBY = 8
  NEARBY_MINUTES = 20

  def show
    @property = Property.published.preload(:destination, :active_listings, :waterfront).find_by!(slug: params[:id])
    @stay = Stay.from_params(params)
    Prices.refresh(@property.active_listings.to_a, current_stay) if current_stay
    @offers = Offer.for_properties([ @property ], current_stay).fetch(@property.id, [])

    walks = @property.walks.preload(:landmark).joins(:landmark).order(:walk_m)
    @featured_walk = featured_walk(walks)
    @nearby_walks = walks.where(walk_m: ..(NEARBY_MINUTES * Walks.config.fetch(:metres_per_minute)))
                         .where.not(id: @featured_walk&.id).limit(NEARBY).to_a
    @route = Walks::Route.new(@featured_walk).lines if @featured_walk
  end

  private

  # The walk to the landmark the visitor searched near, else to the
  # best-known landmark within a short walk, else the shortest walk.
  def featured_walk(walks)
    searched = walks.merge(Landmark.named).find_by(landmarks: { slug: params[:near] }) if params[:near].present?
    searched ||
      walks.where(walk_m: ..(PropertySearch::NEARBY_MINUTES * Walks.config.fetch(:metres_per_minute)))
           .merge(Landmark.named).reorder("landmarks.prominence DESC", :walk_m).first ||
      walks.first
  end
end
