module HomeHelper
  # Destinations grouped by country for the search select. Each option carries
  # its sea and verified count for the searchable list (search_form.js).
  def destination_options(destinations, listed_counts)
    destinations.group_by { |destination| Country.new(destination.country_code) }
      .sort_by { |country, _| country.sort_key }
      .to_h { |country, group| [ country.name, group.map { |destination| destination_option(destination, listed_counts) } ] }
  end

  private

  def destination_option(destination, listed_counts)
    [ destination.name, destination.slug,
      { data: { sea: destination.sea_name, count: listed_counts.fetch(destination.id, 0) } } ]
  end
end
