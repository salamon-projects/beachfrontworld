class SitemapsController < ApplicationController
  def show
    @destinations = Destination.published.ordered
    # Only landmarks with stays to show, so no empty page is indexed.
    @landmarks = Landmark.named.visible
                         .where(id: PropertyWalk.within_reach.where(property_id: Property.published.select(:id)).select(:landmark_id))
                         .select(:id, :slug, :updated_at)
    @properties = Property.published.where(destination: @destinations).select(:id, :slug, :updated_at)
  end
end
