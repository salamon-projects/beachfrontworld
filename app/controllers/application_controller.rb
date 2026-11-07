class ApplicationController < ActionController::Base
  include Pagy::Method

  helper_method :current_stay

  private

  # Sends a request for a page past the end of the results to the last page.
  def redirect_past_last_page(pagy)
    return false unless pagy.page > pagy.last

    query = request.query_parameters.merge("page" => pagy.last).to_query
    redirect_to "#{request.path}?#{query}"
    true
  end

  # The visitor's dates, when they entered valid ones.
  def current_stay
    return @current_stay if defined?(@current_stay)

    stay = Stay.from_params(params)
    @current_stay = stay&.valid? ? stay : nil
  end
end
