module Osm
  module Importers
    # Named tourism=* accommodation. Properties an admin edited or hid keep
    # their name, geometry and any details already set, so a re-import never
    # overrides a manual correction. Properties are never deleted: one that
    # OSM no longer returns is flagged (osm_missing_since) and leaves the site.
    class Accommodations < Base
      KINDS = { "hotel" => "hotel", "motel" => "motel", "guest_house" => "guest_house", "hostel" => "hostel",
                "apartment" => "apartment", "chalet" => "chalet", "camp_site" => "camp_site" }.freeze

      def call
        @seen_ids = Set.new
        elements = client.query(query)
        count = elements.count { |element| import_element(element) }
        flag_missing if elements.any?
        count
      end

      private

      # Flags this destination's OSM properties inside the box that the query
      # did not return (deleted from OSM, or no longer a named accommodation),
      # and clears the flag on those that are back.
      def flag_missing
        Property.where(id: @seen_ids.to_a).where.not(osm_missing_since: nil).update_all(osm_missing_since: nil)
        destination.properties.where.not(osm_id: nil).where(osm_missing_since: nil).where.not(id: @seen_ids.to_a)
                   .where(*inside_bbox("properties.lonlat")).update_all(osm_missing_since: Time.current)
      end

      def selectors
        %w[node way relation].map { |type| %(#{type}["tourism"~"^(#{KINDS.keys.join('|')})$"]["name"]) }
      end

      def import_element(element)
        point = element.point or return false
        name = element.tags["name"].presence or return false

        property = Property.find_or_initialize_by(osm_type: element.type, osm_id: element.id)
        @seen_ids << property.id if property.persisted?
        if property.new_record?
          property.assign_attributes(destination:, kind: KINDS.fetch(element.tags["tourism"], "hotel"))
        end
        unreviewed = !property.reviewed?
        details = details(element.tags)
        details = details.select { |attribute, _| property.public_send(attribute).blank? } unless unreviewed
        property.assign_attributes(details)
        property.assign_attributes(name:, lonlat: point, footprint: element.polygon) if unreviewed
        property.save!
        @seen_ids << property.id
        true
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("Skipping OSM #{element.type}/#{element.id}: #{e.message}")
        false
      end

      def details(tags)
        stars = tags["stars"].to_s[/\A[1-5]/]&.to_i
        website = [ tags["website"], tags["contact:website"] ].compact.map(&:strip).find { |url| url.match?(Property::WEBSITE_FORMAT) }
        street = [ tags["addr:street"], tags["addr:housenumber"] ].compact.join(" ").presence
        address = [ street, tags["addr:city"] || tags["addr:place"] ].compact.join(", ").presence

        { stars:, website:, address: }.compact
      end
    end
  end
end
