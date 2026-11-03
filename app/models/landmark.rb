# A place visitors want to stay near, imported from OpenStreetMap by
# Osm::Importers::Landmarks. Properties are measured against it on foot (see
# Walks::Measurement).
class Landmark < ApplicationRecord
  include Sluggable

  KINDS = %w[attraction museum historic place_of_worship viewpoint square pedestrian_street park
             beach station market].freeze

  belongs_to :destination
  has_many :walks, class_name: "PropertyWalk", dependent: :delete_all

  enum :kind, KINDS.index_by(&:itself), validate: true

  validates :osm_type, :osm_id, :geom, presence: true

  before_validation :assign_unnamed_slug, if: -> { slug.blank? && name.blank? }
  before_save :build_search_text

  scope :named, -> { where.not(name: nil) }
  scope :by_prominence, -> { order(prominence: :desc, name: :asc, id: :asc) }

  # Named landmarks whose names (in any language) resemble the text, the
  # best match first. Typos and missing accents are tolerated.
  def self.search(text)
    query = normalize(text)
    return none if query.blank?

    named.where("? <% landmarks.search_text", query)
         .order(Arel.sql(sanitize_sql_array([ "word_similarity(?, landmarks.search_text) DESC", query ])))
         .order(prominence: :desc, id: :asc)
  end

  # Lowercase ASCII words: "Sagrada Família" → "sagrada familia".
  def self.normalize(text)
    I18n.transliterate(text.to_s.unicode_normalize(:nfkc).downcase).gsub(/[^a-z0-9]+/, " ").strip
  end

  def display_name
    name || I18n.t("landmarks.unnamed.#{kind}")
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
