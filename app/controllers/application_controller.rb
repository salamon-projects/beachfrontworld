class ApplicationController < ActionController::Base
  include Pagy::Method

  helper_method :current_stay

  private

  # Sends a request for a page past the end of the results to the last page.
  def redirect_past_last_page(pagy)
    return false unless pagy.page > pagy.last

    query = request.query_parameters.merge("page" => pagy.last).to_query
    redirect_to "#{request.path}?#{query}"
    true
  end

  MAP_POINTS = 400

  def search_params
    params.slice(*PropertySearch::PARAMS).permit(*PropertySearch::PARAMS)
  end

  # Loads a page of search results with their offers, the map and the
  # landmarks they were measured to. Returns true when it redirected instead.
  def list(search)
    @search = search
    if current_stay
      Prices.refresh(Listing.active.where(property_id: search.filtered.unscope(:select).select(:id)).to_a, current_stay)
    end
    @pagy, @properties = pagy(search.results)
    return true if redirect_past_last_page(@pagy)

    @offers = Offer.for_properties(@properties, current_stay)
    @landmarks = Landmark.where(id: @properties.map { |property| property[:near_landmark_id] }.compact).index_by(&:id)
    points = search.target? ? search.filtered.order(Arel.sql("near_walk_m")) : search.filtered
    @map_data = helpers.destination_map_data(search.destination, points.limit(MAP_POINTS).preload(:waterfront).map do |property|
      helpers.map_point(property, url: property_path(property, helpers.stay_params))
    end)
    false
  end

  # The visitor's dates, when they entered valid ones.
  def current_stay
    return @current_stay if defined?(@current_stay)

    stay = Stay.from_params(params)
    @current_stay = stay&.valid? ? stay : nil
  end
end
