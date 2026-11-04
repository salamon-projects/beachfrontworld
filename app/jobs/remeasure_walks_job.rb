# Measures every walk again after an admin raised the walking limit
# (SiteSetting#max_walk_m), so longer walks are stored too: curated
# destinations over the network they imported, searched places by
# MeasureLandmarkJob, which fetches the wider area around each first.
# Lowering the limit needs none of this: longer walks are only hidden.
class RemeasureWalksJob < ApplicationJob
  queue_as :default

  def perform
    Destination.curated.find_each { |destination| Walks::Measurement.new(destination.landmarks.source_import).call }
    Landmark.source_search.find_each(&:request_measurement!)
  end
end
