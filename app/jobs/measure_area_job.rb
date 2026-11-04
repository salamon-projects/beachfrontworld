# Finishes the area fetched around a searched landmark after
# MeasureLandmarkJob has listed its stays: fetches water, beaches and roads
# and measures the waterfront of the properties there (Osm::AreaImport),
# and measures the walks from the properties the fetch brought in or moved
# to the other measured landmarks within reach.
class MeasureAreaJob < ApplicationJob
  queue_as :areas
  discard_on ActiveRecord::RecordNotFound
  retry_on Osm::OverpassClient::Error, wait: 10.minutes, attempts: 3

  def perform(landmark_id, moved_property_ids = [])
    landmark = Landmark.find(landmark_id)
    area = landmark.walk_area
    Osm::AreaImport.new(landmark.destination, bbox: area).waterfront
    return if moved_property_ids.empty?

    south, west, north, east = area
    landmarks = Landmark.where.not(measured_at: nil)
                        .where("ST_DWithin(geom, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography, ?)",
                               west, south, east, north, Walks.config.fetch(:max_walk_m))
    Walks::Measurement.new(landmarks).call(property_ids: moved_property_ids)
  end
end
