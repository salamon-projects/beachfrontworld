module Osm
  # Imports every OSM layer for a destination, then reclassifies its
  # properties against the fresh geometry.
  class DestinationImport
    LAYERS = {
      coastline: Importers::Coastline,
      inland_water: Importers::InlandWater,
      beaches: Importers::Beaches,
      roads: Importers::Roads,
      accommodations: Importers::Accommodations
    }.freeze

    # progress, when given, is called as progress.(step, steps_done, steps_total)
    # before each layer and while measuring.
    def initialize(destination, client: OverpassClient.new, progress: nil)
      @destination = destination
      @client = client
      @progress = progress || ->(*) { }
    end

    # Returns the number of imported features per layer, how many map
    # features were removed because OSM no longer has them, how many
    # properties OSM no longer has, and how many could not be measured.
    def call
      total = LAYERS.size + 1
      removed = 0
      counts = LAYERS.each_with_index.to_h do |(layer, importer_class), index|
        @progress.call(layer.to_s, index, total)
        importer = importer_class.new(@destination, client: @client)
        imported = importer.call
        removed += importer.removed
        [ layer, imported ]
      end
      counts.merge(removed_features: removed, missing_from_osm: @destination.properties.missing_from_osm.count,
                   measurement_failures: classify_properties(step: total - 1, total:))
    end

    private

    # A broken OSM geometry must not stop the other properties from being
    # measured; failures are logged and the property keeps its old result.
    def classify_properties(step:, total:)
      failures = 0
      count = @destination.properties.count
      @destination.properties.find_each.with_index do |property, index|
        @progress.call("measuring #{index}/#{count}", step, total) if (index % 25).zero?
        Waterfront::Classification.new(property).call
      rescue ActiveRecord::StatementInvalid => e
        failures += 1
        Rails.logger.error("Could not measure property #{property.id} (#{property.slug}): #{e.message}")
      end
      failures
    end
  end
end
