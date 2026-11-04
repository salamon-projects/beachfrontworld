# Walks are measured on demand around whatever a visitor searches for, so
# the walk network becomes one shared map instead of a copy per destination,
# and map_areas records which parts of the map have been fetched from OSM.
class MeasureOnDemand < ActiveRecord::Migration[8.1]
  def up
    create_table :map_areas do |t|
      t.st_polygon :geom, geographic: true, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
      t.index :geom, using: :gist
    end

    # Destinations already imported have their whole box fetched.
    execute <<~SQL
      INSERT INTO map_areas (geom, fetched_at, created_at, updated_at)
      SELECT d.area, COALESCE(MAX(r.finished_at), NOW()), NOW(), NOW()
      FROM destinations d LEFT JOIN import_runs r ON r.destination_id = d.id AND r.status = 'succeeded'
      WHERE EXISTS (SELECT 1 FROM walk_edges e WHERE e.destination_id = d.id)
      GROUP BY d.id
    SQL

    # Overlapping destinations may hold the same ways and nodes.
    execute <<~SQL
      DELETE FROM walk_edges e USING walk_edges other
      WHERE e.osm_way_id = other.osm_way_id AND e.source = other.source AND e.target = other.target AND e.id > other.id
    SQL
    execute <<~SQL
      UPDATE walk_vertices v SET busy = true
      WHERE NOT v.busy AND EXISTS (SELECT 1 FROM walk_vertices o WHERE o.node_id = v.node_id AND o.busy)
    SQL
    execute "DELETE FROM walk_vertices v USING walk_vertices other WHERE v.node_id = other.node_id AND v.id > other.id"

    remove_reference :walk_edges, :destination, foreign_key: true, index: false
    add_column :walk_edges, :seen_at, :datetime
    add_index :walk_edges, :osm_way_id

    remove_reference :walk_vertices, :destination, foreign_key: true, index: false
    add_column :walk_vertices, :seen_at, :datetime
    add_index :walk_vertices, :node_id, unique: true

    # Destinations created for a search, which grow with each place searched
    # in them, unlike the curated ones an admin imports whole.
    add_column :destinations, :on_demand, :boolean, null: false, default: false

    # "import": from a destination's OSM import; "search": found for a visitor.
    add_column :landmarks, :source, :string, null: false, default: "import"
    add_column :landmarks, :measured_at, :datetime
    add_column :landmarks, :measure_requested_at, :datetime
    add_column :landmarks, :measure_failed_at, :datetime
    add_index :landmarks, %i[osm_type osm_id]
    execute "UPDATE landmarks SET measured_at = updated_at"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
