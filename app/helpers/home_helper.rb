module HomeHelper
  # Destinations grouped by country for the search select. Each option carries
  # its sea and verified count for the searchable list (search_form.js).
  def destination_options(destinations, listed_counts)
    destinations.group_by(&:country_name).transform_values do |group|
      group.map do |destination|
        [ destination.name, destination.slug,
          { data: { sea: destination.sea_name, count: listed_counts.fetch(destination.id, 0) } } ]
      end
    end
  end
end
