# Stays near one landmark, ordered by the measured walk.
class LandmarksController < ApplicationController
  def show
    @landmark = Landmark.named.joins(:destination).merge(Destination.published).find_by!(slug: params[:id])
    @stay = Stay.from_params(params)
    return if list(PropertySearch.new(destination: @landmark.destination, landmark: @landmark, stay: current_stay,
                                      params: search_params))

    @map_data[:landmarks] = [ helpers.landmark_map_point(@landmark) ]
  end
end
