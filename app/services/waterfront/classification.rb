module Waterfront
  # Measures and classifies a property and stores the result as its
  # Verifications::Waterfront.
  class Classification
    def initialize(property, measurer: Measurer.new, classifier: Classifier.new)
      @property = property
      @measurer = measurer
      @classifier = classifier
    end

    def call
      measurement = @measurer.measure(@property)
      category = @classifier.category_for(measurement)
      verification = @property.waterfront || @property.build_waterfront
      verification.update!(
        category:, distance_m: measurement.distance_to_water_m, evidence: evidence(measurement), measured_at: Time.current
      )

      @property.update_columns(coord_mismatch_m: measurement.coord_mismatch_m, updated_at: Time.current)
      @property
    end

    private

    def evidence(measurement)
      point = measurement.water_point
      {
        water_feature_id: measurement.water_feature_id,
        water_kind: measurement.water_kind,
        water_name: measurement.water_name,
        water_point: point && [ point.x, point.y ],
        distance_to_beach_m: measurement.distance_to_beach_m,
        beach_surface: measurement.beach_surface,
        crosses_road: measurement.crosses_road,
        crosses_promenade: measurement.crosses_promenade
      }
    end
  end
end
