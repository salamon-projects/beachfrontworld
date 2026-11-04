# Measures the walks to one landmark, typically a place a visitor just
# searched for, while its page waits. The first time, results arrive in
# stages so the visitor need not wait for the whole map: the stays around it
# (a quick query), then the shorter walks (NEAR_SHARE of the limit) over a
# small part of the network, then the rest. A walk never leaves a box as far
# around the landmark as it is long, so the early walks are already exact. A part of
# the map fetched recently (MapArea) is not fetched again. The rest of the
# area is left to MeasureAreaJob. Overpass gets a few quick retries, and a
# server that has not answered in 90 seconds is given up for the next one,
# rather than the import's long waits.
class MeasureLandmarkJob < ApplicationJob
  NEAR_SHARE = 0.5

  queue_as :areas
  discard_on ActiveRecord::RecordNotFound

  def perform(landmark_id)
    landmark = Landmark.find(landmark_id)
    area = landmark.walk_area
    unless MapArea.covers?(area)
      moved = import(landmark, area).stays
      measure_near(landmark) unless landmark.measured?
      import(landmark, area).network
    end
    Walks::Measurement.new(Landmark.where(id: landmark.id)).call
    MeasureAreaJob.perform_later(landmark.id, moved) if moved
  rescue StandardError => e
    # The landmark page offers to try again.
    landmark&.update_columns(measure_failed_at: Time.current)
    raise unless e.is_a?(Osm::OverpassClient::Error)

    Rails.logger.warn("Could not measure landmark #{landmark_id}: #{e.message}")
  end

  def self.near_walk_m
    (Walks.max_walk_m * NEAR_SHARE).round(-1)
  end

  private

  def import(landmark, bbox)
    Osm::AreaImport.new(landmark.destination, bbox:, client: Osm::OverpassClient.new(timeout: 90, attempts: 3, backoff: 5))
  end

  def measure_near(landmark)
    near = landmark.walk_area(self.class.near_walk_m)
    import(landmark, near).network unless MapArea.covers?(near)
    Walks::Measurement.new(Landmark.where(id: landmark.id), config: Walks.config.merge(max_walk_m: self.class.near_walk_m))
                      .call(complete: false)
  end
end
