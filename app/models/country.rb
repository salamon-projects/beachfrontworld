# A country with published destinations, for the /beachfront/:country pages.
# Not stored: it comes from the destinations' country codes.
Country = Data.define(:code) do
  # Countries listed before the rest (which follow alphabetically) wherever
  # countries are listed: home tabs and sections, search select, footer.
  FEATURED = %w[GR].freeze

  def self.published
    Destination.published.distinct.pluck(:country_code).map { |code| new(code) }.sort_by(&:sort_key)
  end

  def self.find_published(slug)
    published.find { |country| country.slug == slug }
  end

  def name
    I18n.t("countries.#{code}", default: code)
  end

  def sort_key
    [ FEATURED.index(code) || FEATURED.size, name ]
  end

  def slug
    name.parameterize
  end

  def to_param
    slug
  end

  def destinations
    Destination.published.where(country_code: code).ordered
  end
end
