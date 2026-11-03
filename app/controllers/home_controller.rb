class HomeController < ApplicationController
  EXAMPLES = 5

  def index
    @destinations = Destination.published.ordered.to_a
    @listed_counts = Property.published.group(:destination_id).count
    @landmark_counts = Landmark.named.where(destination: @destinations).group(:destination_id).count
    @examples = Landmark.named.where(destination: @destinations).by_prominence.limit(EXAMPLES)
  end
end
