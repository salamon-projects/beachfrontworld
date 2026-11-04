# A place visitors want to stay near, imported from OpenStreetMap with a
# destination (Osm::Importers::Landmarks) or found when a visitor searched
# for it (Search::Locator). Properties are measured against it on foot (see
# Walks::Measurement), on demand for searched ones (MeasureLandmarkJob).
class Landmark < ApplicationRecord
  include Sluggable

  METRES_PER_DEGREE = 111_320.0
  KINDS = %w[attraction museum historic place_of_worship viewpoint square pedestrian_street park
             beach station market place].freeze
  SOURCES = %w[import search].freeze
  # A measurement requested longer ago than this, without a result, has
  # stopped (a restart, a lost job) and may be requested again.
  MEASURING_STALE_AFTER = 30.minutes

  belongs_to :destination
  has_many :walks, class_name: "PropertyWalk", dependent: :delete_all

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :source, SOURCES.index_by(&:itself), validate: true, prefix: true

  validates :osm_type, :osm_id, :geom, presence: true

  before_validation :assign_unnamed_slug, if: -> { slug.blank? && name.blank? }
  before_save :build_search_text

  scope :named, -> { where.not(name: nil) }
  scope :searched, -> { source_search }
  # On the site: in a published destination, or searched for by a visitor
  # (its town may be a destination not published yet).
  scope :visible, -> { joins(:destination).where("destinations.published OR landmarks.searched_at IS NOT NULL") }
  # Close enough to a point for a walk to be measured.
  scope :within_walk_of, ->(point) {
    where("ST_DWithin(geom, ST_GeogFromText(?), ?)", point.as_text, Walks.config.fetch(:max_walk_m))
  }
  scope :by_prominence, -> { order(prominence: :desc, name: :asc, id: :asc) }

  # Named landmarks whose names (in any language) resemble the text, the
  # best match first, with how well it matched (0–1) as search_score. Typos
  # and missing accents are tolerated.
  def self.search(text)
    query = normalize(text)
    return none if query.blank?

    score = sanitize_sql_array([ "word_similarity(?, landmarks.search_text)", query ])
    named.where("? <% landmarks.search_text", query)
         .select("landmarks.*", "#{score} AS search_score")
         .order(Arel.sql("search_score DESC"), prominence: :desc, id: :asc)
  end

  # Lowercase ASCII words: "Sagrada Família" → "sagrada familia".
  def self.normalize(text)
    I18n.transliterate(text.to_s.unicode_normalize(:nfkc).downcase).gsub(/[^a-z0-9]+/, " ").strip
  end

  def measured?
    measured_at.present?
  end

  def measuring?
    return false unless measure_requested_at && measure_requested_at > MEASURING_STALE_AFTER.ago

    [ measured_at, measure_failed_at ].compact.none? { |at| at >= measure_requested_at }
  end

  def measure_failed?
    measure_failed_at.present? && !measuring? && (measured_at.nil? || measure_failed_at > measured_at)
  end

  # Queues measuring the walks to it (fetching the map around it first when
  # needed), unless that is already under way.
  def request_measurement!
    return if measuring?

    update!(measure_requested_at: Time.current)
    MeasureLandmarkJob.perform_later(id)
  end

  # [south, west, north, east] around the landmark holding every walk to
  # it up to walk_m (by default the longest measured), and the way from a
  # property to the network.
  def walk_area(walk_m = Walks.config.fetch(:max_walk_m))
    margin = walk_m + Walks.config.fetch(:max_access_m)
    west, south, east, north = self.class.where(id:).pick(*%w[XMin YMin XMax YMax].map { |f| Arel.sql("ST_#{f}(geom::geometry)") })
    dlat = margin / METRES_PER_DEGREE
    dlon = margin / (METRES_PER_DEGREE * Math.cos((south + north) / 2 * Math::PI / 180))
    [ south - dlat, west - dlon, north + dlat, east + dlon ].map { |degrees| degrees.round(6) }
  end

  def display_name
    name || I18n.t("landmarks.unnamed.#{kind}")
  end

  # [lon, lat] of a point on the landmark, for its map marker.
  def position
    @position ||= self.class.where(id:).pick(Arel.sql("ST_X(ST_PointOnSurface(geom::geometry))"),
                                             Arel.sql("ST_Y(ST_PointOnSurface(geom::geometry))"))
  end

  private

  def assign_unnamed_slug
    self.slug = "#{kind.to_s.dasherize}-#{osm_id}"
  end

  def build_search_text
    words = [ name, local_name, *names.values ].compact.map { |value| self.class.normalize(value) }
    self.search_text = words.compact_blank.uniq.join(" | ")
  end
end
