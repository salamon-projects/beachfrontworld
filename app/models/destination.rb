class Destination < ApplicationRecord
  include Sluggable

  has_many :properties, dependent: :restrict_with_error
  has_many :import_runs, dependent: :delete_all

  normalizes :country_code, with: ->(code) { code.strip.upcase }

  attribute :south, :float
  attribute :west, :float
  attribute :north, :float
  attribute :east, :float

  validates :name, :country_code, presence: true
  validates :country_code, format: { with: /\A[A-Z]{2}\z/ }
  validates :zoom, numericality: { only_integer: true, in: 3..18 }
  validates :area, :center, presence: true
  validate :bbox_is_ordered

  before_validation :build_area_from_bbox, if: :bbox_given?

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position, :name) }

  after_initialize :load_bbox_from_area, if: -> { has_attribute?(:area) && area.present? && !bbox_given? }

  # [south, west, north, east], the order Overpass expects.
  def bbox
    [ south, west, north, east ]
  end

  def country_name
    I18n.t("countries.#{country_code}", default: country_code)
  end

  private

  def bbox_given?
    [ south, west, north, east ].all?(&:present?)
  end

  def bbox_is_ordered
    return unless bbox_given?

    errors.add(:north, :greater_than, count: :south) unless north > south
    errors.add(:east, :greater_than, count: :west) unless east > west
  end

  def build_area_from_bbox
    return unless north > south && east > west

    self.area = Geo.bbox_polygon(south:, west:, north:, east:)
    self.center = Geo.point(lon: (west + east) / 2.0, lat: (south + north) / 2.0)
  end

  def load_bbox_from_area
    lons = area.exterior_ring.points.map(&:x)
    lats = area.exterior_ring.points.map(&:y)
    self.south, self.north = lats.minmax
    self.west, self.east = lons.minmax
    clear_attribute_changes(%i[south west north east])
  end
end
