class Property < ApplicationRecord
  include Sluggable

  KINDS = %w[hotel resort apartment guest_house hostel motel villa chalet camp_site].freeze
  WEBSITE_FORMAT = %r{\Ahttps?://[^\s]+\z}i

  belongs_to :destination
  has_many :verifications, dependent: :destroy
  has_one :waterfront, class_name: "Verifications::Waterfront", inverse_of: :property
  has_many :walks, class_name: "PropertyWalk", dependent: :delete_all
  has_many :listings, dependent: :destroy
  has_many :active_listings, -> { active }, class_name: "Listing", inverse_of: :property
  has_many :price_quotes, through: :active_listings

  enum :kind, KINDS.index_by(&:itself), validate: true

  attribute :latitude, :float
  attribute :longitude, :float

  # Set by imports, which measure all the properties they bring in at once.
  attr_accessor :skip_measurement

  before_validation :build_lonlat_from_coordinates, if: :coordinates_entered?
  after_initialize :load_coordinates, if: -> { has_attribute?(:lonlat) && lonlat.present? && latitude.nil? }

  validates :name, :lonlat, presence: true
  validates :stars, numericality: { only_integer: true, in: 1..5 }, allow_nil: true
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
  validates :website, format: { with: WEBSITE_FORMAT }, allow_blank: true

  after_commit :enqueue_classification, on: %i[create update], if: -> { geometry_changed? && !skip_measurement }

  # Shown on the site: measured within walking distance of a landmark, or on
  # the waterfront, unless an admin hid it or OSM no longer has it.
  scope :published, -> {
    where(hidden_at: nil, osm_missing_since: nil)
      .where(PropertyWalk.where("property_walks.property_id = properties.id").arel.exists
        .or(Verifications::Waterfront.listed.where("verifications.property_id = properties.id").arel.exists))
  }
  scope :hidden, -> { where.not(hidden_at: nil) }

  # Best waterfront first, then the shortest measured distance. Unmeasured
  # properties come last.
  scope :by_waterfront, -> { left_joins(:waterfront).order(*waterfront_sort_key.map { |sql| Arel.sql(sql) }) }

  # Properties that an OTA labels beachfront although our measurement does not
  # support it.
  scope :beachfront_claim_conflicts, -> {
    joins(:waterfront)
      .where(id: Listing.where(claims_beachfront: true).select(:property_id))
      .where(verifications: { category: %w[not_waterfront walkable] })
  }

  # The last OSM import no longer found it (see Osm::Importers::Accommodations).
  scope :missing_from_osm, -> { where.not(osm_missing_since: nil) }

  scope :with_coordinate_mismatch, -> {
    where("properties.coord_mismatch_m > ?", Waterfront.config.fetch(:coordinate_mismatch_m))
  }

  # The by_waterfront order as SQL expressions without NULLs (so rows can be
  # compared), ending with the id so the order is total.
  def self.waterfront_sort_key
    @waterfront_sort_key ||= [
      sanitize_sql_array([ "COALESCE(array_position(ARRAY[?]::varchar[], verifications.category), 99)",
                           Verifications::Waterfront::CATEGORIES ]),
      "COALESCE(verifications.distance_m, 2147483647)",
      "properties.name",
      "properties.id"
    ].freeze
  end

  # The properties just before and after this one in by_waterfront order
  # within scope. Works when this one is no longer in scope, for example right
  # after it was reviewed off the "To review" list.
  def neighbors_in(scope)
    key_sql = self.class.waterfront_sort_key.map { |sql| Arel.sql(sql) }
    key = Property.left_joins(:waterfront).where(id:).pick(*key_sql)
    row = Arel::Nodes::Grouping.new(key_sql)
    values = Arel::Nodes::Grouping.new(key.map { |value| Arel::Nodes.build_quoted(value) })
    scope = scope.left_joins(:waterfront)
    before = scope.where(Arel::Nodes::LessThan.new(row, values))
    after = scope.where(Arel::Nodes::GreaterThan.new(row, values))

    { previous: before.reorder(*key_sql.map(&:desc)).first, following: after.reorder(*key_sql).first,
      position: (before.count + 1 if scope.exists?(id)), total: scope.count }
  end

  def listed?
    persisted? && self.class.published.exists?(id)
  end

  def hidden?
    hidden_at.present?
  end

  # An admin has edited or hidden it, so imports must not move it or
  # overwrite what was entered.
  def reviewed?
    reviewed_at.present?
  end

  def lonlat=(value)
    super
    load_coordinates if lonlat
  end

  def coordinate_mismatch?
    coord_mismatch_m.to_i > Waterfront.config.fetch(:coordinate_mismatch_m)
  end

  private

  def coordinates_entered?
    (attribute_changed?(:latitude) || attribute_changed?(:longitude)) && latitude.present? && longitude.present?
  end

  def build_lonlat_from_coordinates
    point = Geo.point(lon: longitude, lat: latitude)
    self.lonlat = point unless lonlat && lonlat.x == point.x && lonlat.y == point.y
  end

  def load_coordinates
    self.latitude = lonlat.y
    self.longitude = lonlat.x
    clear_attribute_changes(%i[latitude longitude])
  end

  def geometry_changed?
    saved_change_to_lonlat? || saved_change_to_footprint?
  end

  def enqueue_classification
    ClassifyPropertyJob.perform_later(id)
  end
end
