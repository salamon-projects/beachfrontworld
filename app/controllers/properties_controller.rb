class PropertiesController < ApplicationController
  def show
    @property = Property.published.preload(:destination, :active_listings, :waterfront).find_by!(slug: params[:id])
    @stay = Stay.from_params(params)
    Prices.refresh(@property.active_listings.to_a, current_stay) if current_stay
    @offers = Offer.for_properties([ @property ], current_stay).fetch(@property.id, [])
  end
end
