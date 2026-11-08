# Weekly check of the websites of listed properties (Websites::Checker), so
# the "Official website" link is only shown when it leads somewhere.
class CheckWebsitesJob < ApplicationJob
  queue_as :default

  def perform(scope = Property.published.with_website)
    checker = Websites::Checker.new
    scope.find_each do |property|
      checker.record(property)
    rescue StandardError => e
      Rails.logger.warn("Website check failed for property #{property.id}: #{e.class}: #{e.message}")
    end
  end
end
