module Osm
  # Fetches the OSM data around one searched place, a quicker cousin of
  # DestinationImport for a single box (see MeasureLandmarkJob). #stays
  # fetches the accommodation (a small, quick query, so a visitor sees the
  # stays early); #network the walk network, recording the box as fetched
  # (MapArea) on the understanding that its stays were fetched before;
  # #waterfront
  # fetches water, beaches and, where there is water, roads, and re-measures
  # the waterfront of the properties in the box.
  #
  # Properties are not measured one by one as they are imported; the
  # callers measure them together.
  class AreaImport
    WATER_LAYERS = { coastline: Importers::Coastline, inland_water: Importers::InlandWater, beaches: Importers::Beaches }.freeze

    # New properties belong to destination; bbox is [south, west, north, east].
    def initialize(destination, bbox:, client: OverpassClient.new)
      @destination = destination
      @bbox = bbox
      @client = client
    end

    # Returns the ids of the properties created or moved.
    def stays
      importer = Importers::Accommodations.new(@destination, client: @client, bbox: @bbox)
      importer.call
      importer.moved_ids
    end

    # Returns the number of edges imported.
    def network
      count = Importers::WalkNetwork.new(@destination, client: @client, bbox: @bbox).call
      MapArea.record!(@bbox) if count.positive?
      count
    end

    def waterfront
      counts = import(WATER_LAYERS)
      # Roads only decide whether a property is directly on the water.
      counts.merge!(import(roads: Importers::Roads)) if (counts[:coastline] + counts[:inland_water]).positive?
      counts.merge(measured: classify_properties)
    end

    private

    def import(layers)
      layers.transform_values { |importer| importer.new(@destination, client: @client, bbox: @bbox).call }
    end

    # A broken OSM geometry must not stop the other properties from being
    # measured.
    def classify_properties
      south, west, north, east = @bbox
      properties = Property.where(osm_missing_since: nil)
                           .where("lonlat && ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography", west, south, east, north)
      properties.find_each.count do |property|
        Waterfront::Classification.new(property).call
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.error("Could not measure property #{property.id} (#{property.slug}): #{e.message}")
        false
      end
    end
  end
end
