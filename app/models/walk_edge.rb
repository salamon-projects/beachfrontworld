# One stretch of walkable OSM way between two junctions (see
# Osm::Importers::WalkNetwork). source and target are OSM node ids.
class WalkEdge < ApplicationRecord
  belongs_to :destination
end
