class HomeController < ApplicationController
  def index
    @destinations = Destination.published.ordered.to_a
    @listed_counts = Property.published.group(:destination_id).count
    @direct_counts = Property.published.joins(:waterfront).where(verifications: { category: "direct" }).group(:destination_id).count
  end
end
