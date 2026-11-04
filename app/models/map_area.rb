# A part of the map whose OSM data (walk network, accommodation, water) was
# fetched, so measuring near it needs no new download while it is fresh.
class MapArea < ApplicationRecord
  # OSM data older than this is fetched again before measuring.
  FRESH_FOR = 30.days

  validates :geom, :fetched_at, presence: true

  # Whether fresh areas together cover the box [south, west, north, east].
  def self.covers?(bbox, since: FRESH_FOR.ago)
    south, west, north, east = bbox
    box = "ST_MakeEnvelope(:west, :south, :east, :north, 4326)"
    where(fetched_at: since..).where("geom && #{box}::geography", west:, south:, east:, north:)
      .pick(Arel.sql(sanitize_sql_array([ "COALESCE(ST_CoveredBy(#{box}, ST_Union(geom::geometry)), false)",
                                          { west:, south:, east:, north: } ])))
  end

  def self.record!(bbox, fetched_at: Time.current)
    south, west, north, east = bbox
    create!(geom: Geo.bbox_polygon(south:, west:, north:, east:), fetched_at:)
  end
end
