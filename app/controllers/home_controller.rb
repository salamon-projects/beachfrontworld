class HomeController < ApplicationController
  EXAMPLES = 5
  # Stays shown in the hero as a sample of what a search finds.
  SHOWCASE_WALKS = 3

  def index
    @destinations = Destination.published.ordered.to_a
    @listed_counts = Property.published.group(:destination_id).count
    @landmark_counts = Landmark.named.where(destination: @destinations).group(:destination_id).count
    @examples = Landmark.named.where(destination: @destinations).by_prominence.limit(EXAMPLES).to_a
    @showcase, @showcase_walks = showcase
    @example_queries = example_queries
  end

  private

  # The best-known landmark with measured stays, and its closest ones: a real
  # result instead of a picture of one.
  def showcase
    @examples.each do |landmark|
      walks = landmark.walks.within_reach.where(property: Property.published).includes(:property)
                      .order(:walk_m, :id).limit(SHOWCASE_WALKS).to_a
      return [ landmark, walks ] if walks.any?
    end
    nil
  end

  # Searches typed the way a visitor might, built from places we have, so
  # each one leads somewhere.
  def example_queries
    queries = []
    queries << "Apartment within 10 minutes of #{@showcase.name}" if @showcase
    other = @examples.find { |landmark| landmark != @showcase }
    queries << "Hotel a 5-minute walk from #{other.name}" if other
    beach_destination = @destinations.find { |destination| destination.landmarks.beach.exists? }
    queries << "Near a beach in #{beach_destination.name}" if beach_destination
    queries
  end
end
