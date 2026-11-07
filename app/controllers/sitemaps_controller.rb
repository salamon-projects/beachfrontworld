class SitemapsController < ApplicationController
  def show
    @destinations = Destination.published.ordered
    @properties = Property.published.where(destination: @destinations).select(:id, :slug, :updated_at)
  end
end
