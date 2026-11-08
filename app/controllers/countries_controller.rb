class CountriesController < ApplicationController
  PER_DESTINATION = 3
  HIGHLIGHTS = 12

  def show
    @country = Country.find_published(params[:id]) or raise ActiveRecord::RecordNotFound
    @destinations = @country.destinations.to_a
    published = Property.published.where(destination: @destinations)
    direct = published.joins(:waterfront).where(verifications: { category: "direct" })
    @listed_counts = published.group(:destination_id).count
    @direct_counts = direct.group(:destination_id).count
    # The closest few of each coast, so one big destination does not fill the list.
    @highlights = @destinations.flat_map do |destination|
      Property.published.where(destination:).by_waterfront.where(verifications: { category: "direct" })
              .preload(:destination, :waterfront).limit(PER_DESTINATION).to_a
    end
    @highlights = @highlights.sort_by { |property| [ property.waterfront.distance_m || Float::INFINITY, property.name ] }
                             .first(HIGHLIGHTS)
  end
end
