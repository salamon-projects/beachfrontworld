class DestinationsController < ApplicationController
  def show
    @destination = Destination.published.find_by!(slug: params[:id])
    @stay = Stay.from_params(params)
    @top_landmarks = @destination.landmarks.named.by_prominence.limit(10)
    list(PropertySearch.new(destination: @destination, stay: current_stay, params: search_params))
  end
end
