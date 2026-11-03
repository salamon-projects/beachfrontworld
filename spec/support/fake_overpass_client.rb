# Serves a fixture file instead of calling Overpass. The fixture groups
# elements by layer; each query gets the group whose selector it contains.
class FakeOverpassClient
  # Checked in order: the walk network query also mentions "highway".
  LAYER_SELECTORS = {
    "walk_network" => "(footway|path|steps|",
    "coastline" => '"natural"="coastline"',
    "inland_water" => '"natural"="water"',
    "beaches" => '"natural"="beach"',
    "roads" => '"highway"',
    "accommodations" => '"tourism"'
  }.freeze

  attr_reader :queries

  def initialize(fixture = "sample_bay")
    @layers = JSON.parse(Rails.root.join("spec/fixtures/files/overpass/#{fixture}.json").read)
    @queries = []
  end

  def query(ql)
    @queries << ql
    layer = LAYER_SELECTORS.find { |_, selector| ql.include?(selector) }&.first
    Array(@layers[layer]).map { |json| Osm::Element.from_json(json) }
  end
end
