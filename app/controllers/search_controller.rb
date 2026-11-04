# Turns what a visitor typed into the page that answers it: stays near one
# landmark, near a kind of place in a destination, or in a destination. A
# place we have not measured is looked up on the map and measured on its
# landmark page. When it is not clear where to go, shows the choices.
class SearchController < ApplicationController
  # New places one visitor may look up on the map per hour: each one costs
  # OpenStreetMap servers a download.
  LOCATE_PER_HOUR = 20

  def show
    return redirect_to_destination if params[:destination].present?

    @query = params[:q].to_s.squish.first(Search::Interpreter::MAX_INPUT)
    return redirect_to(root_path, alert: t("search.enter_place")) if @query.blank?

    @outcome = Search::Resolver.new.call(@query)
    @extra = (Stay.from_params(params)&.to_params || {})
             .merge(max_minutes: @outcome.max_minutes, kind: @outcome.property_kind).compact
    locate if @outcome.status == :locate
    return if performed?

    case @outcome.status
    when :landmark then redirect_to landmark_path(@outcome.landmark, @extra)
    when :kind then redirect_to destination_path(@outcome.destination, @extra.merge(near: @outcome.kind))
    when :destination then redirect_to destination_path(@outcome.destination, @extra)
    else
      @destinations = Destination.published.curated.ordered unless @outcome.status.in?(%i[choices choose_destination])
    end
  end

  private

  # Finds the place on the map; its landmark page measures it. When the map
  # has nothing, a destination named in the text is the next best answer.
  def locate
    if locate_limit_reached?
      @status = :busy
      return
    end

    result = Search::Locator.new.call(@outcome.queries)
    return redirect_to(landmark_path(result.landmark, @extra)) if result.status == :found
    return redirect_to(destination_path(@outcome.destination, @extra)) if @outcome.destination

    @status = result.status
    @place = result.place
  end

  def locate_limit_reached?
    count = Rails.cache.increment([ "search-locate", request.remote_ip, Time.current.beginning_of_hour.to_i ], 1,
                                  expires_in: 1.hour)
    count.to_i > LOCATE_PER_HOUR
  end

  # The destination picker of earlier versions of the home page.
  def redirect_to_destination
    destination = Destination.published.find_by(slug: params[:destination])
    if destination
      redirect_to destination_path(destination, Stay.from_params(params)&.to_params || {})
    else
      redirect_to root_path, alert: t("search.choose_destination")
    end
  end
end
