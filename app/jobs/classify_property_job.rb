class ClassifyPropertyJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(property_id)
    Waterfront::Classification.new(Property.find(property_id)).call
  end
end
