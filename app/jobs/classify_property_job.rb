class ClassifyPropertyJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  # Re-measures a property after its position changed: waterfront and walks.
  def perform(property_id)
    property = Property.find(property_id)
    Waterfront::Classification.new(property).call
    Walks::Measurement.new(Landmark.within_walk_of(property.lonlat)).call(property_ids: [ property.id ])
  end
end
