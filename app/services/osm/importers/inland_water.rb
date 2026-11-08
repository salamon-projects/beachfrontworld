module Osm
  module Importers
    # Lakes, reservoirs and lagoons mapped as natural=water polygons. Rivers
    # are left out: a riverbank is not a beach. Multipolygon relations are
    # limited to their first closed outer ring.
    class InlandWater < Base
      KINDS = { "lake" => "lake", "reservoir" => "lake", "lagoon" => "lake" }.freeze

      private

      def model = WaterFeature

      def layer_scope = model.where(kind: KINDS.values.uniq)

      def selectors
        [ 'way["natural"="water"]["water"~"^(lake|reservoir|lagoon)$"]',
          'relation["natural"="water"]["water"~"^(lake|reservoir|lagoon)$"]' ]
      end

      def row_for(element)
        polygon = element.polygon or return
        kind = KINDS[element.tags["water"]] or return

        { osm_type: element.type, osm_id: element.id, kind:, name: element.tags["name"], geom: polygon }
      end
    end
  end
end
