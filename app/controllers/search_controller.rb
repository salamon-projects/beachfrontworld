# Turns what a visitor typed into the page that answers it: stays near one
# landmark, near a kind of place in a destination, or in a destination. When
# that is not clear, shows the choices.
class SearchController < ApplicationController
  def show
    return redirect_to_destination if params[:destination].present?

    @query = params[:q].to_s.squish.first(Search::Interpreter::MAX_INPUT)
    return redirect_to(root_path, alert: t("search.enter_place")) if @query.blank?

    @outcome = Search::Resolver.new.call(@query)
    extra = (Stay.from_params(params)&.to_params || {})
            .merge(max_minutes: @outcome.max_minutes, kind: @outcome.property_kind).compact
    case @outcome.status
    when :landmark then redirect_to landmark_path(@outcome.landmark, extra)
    when :kind then redirect_to destination_path(@outcome.destination, extra.merge(near: @outcome.kind))
    when :destination then redirect_to destination_path(@outcome.destination, extra)
    else
      @extra = extra
      @destinations = Destination.published.ordered if @outcome.status == :none
    end
  end

  private

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
