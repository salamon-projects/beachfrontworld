class ClassifyPropertyJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  # Re-measures a property after its position changed: waterfront and walks.
  def perform(property_id)
    property = Property.find(property_id)
    Waterfront::Classification.new(property).call
    Walks::Measurement.new(property.destination).call(property_ids: [ property.id ])
  end
end
