# Sea coastline or inland water geometry imported from OpenStreetMap.
class WaterFeature < ApplicationRecord
  KINDS = %w[sea lake].freeze

  enum :kind, KINDS.index_by(&:itself), validate: true

  validates :osm_type, :osm_id, :geom, presence: true
end
