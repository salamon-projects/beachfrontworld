# Turns the home page search form into a destination URL.
class SearchController < ApplicationController
  def show
    destination = Destination.published.find_by(slug: params[:destination])
    if destination
      redirect_to destination_path(destination, Stay.from_params(params)&.to_params || {})
    else
      redirect_to root_path, alert: t("search.choose_destination")
    end
  end
end
