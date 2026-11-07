module Osm
  # One element of an Overpass `out geom` response.
  Element = Data.define(:type, :id, :tags, :lat, :lon, :coords, :members) do
    def self.from_json(json)
      new(
        type: json.fetch("type"),
        id: json.fetch("id"),
        tags: json.fetch("tags", {}),
        lat: json["lat"],
        lon: json["lon"],
        coords: coords_from(json["geometry"]),
        members: Array(json["members"]).map { |m| { role: m["role"], coords: coords_from(m["geometry"]) } }
      )
    end

    def self.coords_from(geometry)
      Array(geometry).compact.map { |p| [ p.fetch("lon"), p.fetch("lat") ] }
    end

    def node? = type == "node"
    def way? = type == "way"
    def relation? = type == "relation"

    def closed?
      coords.size >= 4 && coords.first == coords.last
    end

    # Ring for area features: a closed way, or the first closed outer member
    # of a multipolygon relation.
    def area_coords
      return coords if way? && closed?

      members.find { |m| m[:role] == "outer" && m[:coords].size >= 4 && m[:coords].first == m[:coords].last }&.dig(:coords)
    end

    def line
      Geo.line(coords) if way? && coords.size >= 2
    end

    def polygon
      ring = area_coords
      Geo.polygon(ring) if ring
    end

    # Representative point: the node itself, or the mean of the ring's
    # vertices (good enough for building-sized areas).
    def point
      return Geo.point(lon:, lat:) if node? && lat && lon

      vertices = area_coords || coords
      vertices = vertices[0...-1] if vertices.size > 1 && vertices.first == vertices.last
      return if vertices.empty?

      Geo.point(lon: vertices.sum(&:first) / vertices.size, lat: vertices.sum(&:last) / vertices.size)
    end
  end
end
