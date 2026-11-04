# Stays near one landmark, ordered by the measured walk. A landmark not
# measured yet (usually a place just searched for) is measured in the
# background while the page shows what has arrived so far: walks measured,
# then stays found but not measured yet, by straight-line distance.
class LandmarksController < ApplicationController
  # Stays shown while measuring.
  PREVIEW = 30

  rate_limit to: 10, within: 1.hour, only: :measure

  before_action :set_landmark

  def show
    @stay = Stay.from_params(params)
    unless @landmark.measured?
      @landmark.request_measurement! unless @landmark.measure_failed?
      load_preview
      return render :measuring
    end
    return if list(PropertySearch.new(destination: @landmark.destination, landmark: @landmark, stay: current_stay,
                                      params: search_params))

    point = helpers.landmark_map_point(@landmark)
    @map_data.merge!(landmarks: [ point ], center: [ point[:lat], point[:lon] ], zoom: 15)
  end

  # Tries again after measuring failed.
  def measure
    @landmark.request_measurement! unless @landmark.measured?
    redirect_to landmark_path(@landmark, request.query_parameters)
  end

  private

  def load_preview
    walks = @landmark.walks.within_reach.joins(:property).merge(Property.published)
    @measured_count = walks.count
    @walks = walks.preload(:property).order(:walk_m).limit(PREVIEW).to_a
    pending = Property.where(hidden_at: nil, osm_missing_since: nil).where.not(id: walks.select(:property_id))
                      .where("ST_DWithin(lonlat, (SELECT geom FROM landmarks WHERE id = ?), ?)",
                             @landmark.id, Walks.max_walk_m)
    @pending_count = pending.count
    @pending = pending.select("properties.*", Property.sanitize_sql_array(
      [ "ST_Distance(lonlat, (SELECT geom FROM landmarks WHERE id = ?)) AS straight_m", @landmark.id ]
    )).order("straight_m", :id).limit(PREVIEW - @walks.size).to_a
  end

  def set_landmark
    @landmark = Landmark.named.visible.find_by!(slug: params[:id])
  end
end
