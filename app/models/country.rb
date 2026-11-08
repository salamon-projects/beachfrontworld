# A country with published destinations, for the /beachfront/:country pages.
# Not stored: it comes from the destinations' country codes.
Country = Data.define(:code) do
  def self.published
    Destination.published.distinct.pluck(:country_code).map { |code| new(code) }.sort_by(&:name)
  end

  def self.find_published(slug)
    published.find { |country| country.slug == slug }
  end

  def name
    I18n.t("countries.#{code}", default: code)
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
