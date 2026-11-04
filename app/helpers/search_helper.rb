module SearchHelper
  # Why a search did not lead to a page of stays.
  def search_failure(outcome, status, place)
    case status
    when :busy, :unavailable then t("search.#{status}")
    when :too_big then t("search.too_big", place:)
    else outcome.place ? t("search.not_measured_place", place: outcome.place) : t("search.not_found")
    end
  end
end
