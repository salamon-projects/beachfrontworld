# The walkable street and path network of a destination, split at junctions
# so pgRouting can measure walks along it. Vertex ids are OSM node ids.
class CreateWalkNetwork < ActiveRecord::Migration[8.1]
  def change
    # The pgrouting/pgrouting database image ships a newer PostGIS library
    # than the postgis/postgis image it replaces; bring the extension up to it.
    reversible { |direction| direction.up { execute "SELECT postgis_extensions_upgrade()" } }
    enable_extension "pgrouting"
    enable_extension "pg_trgm"
    enable_extension "unaccent"

    create_table :walk_edges do |t|
      t.references :destination, null: false, foreign_key: true, index: false
      t.bigint :osm_way_id, null: false
      t.bigint :source, null: false
      t.bigint :target, null: false
      t.string :highway, null: false
      t.boolean :steps, null: false, default: false
      t.boolean :busy, null: false, default: false
      t.float :length_m, null: false, default: 0
      t.line_string :geom, geographic: true, null: false
      t.index %i[destination_id source]
      t.index %i[destination_id target]
      t.index :geom, using: :gist
    end

    create_table :walk_vertices do |t|
      t.references :destination, null: false, foreign_key: true, index: false
      t.bigint :node_id, null: false
      # On a primary, secondary or trunk road: walking across it counts as a
      # busy crossing.
      t.boolean :busy, null: false, default: false
      t.st_point :geom, geographic: true, null: false
      t.index %i[destination_id node_id], unique: true
      t.index :geom, using: :gist
    end
  end
end
