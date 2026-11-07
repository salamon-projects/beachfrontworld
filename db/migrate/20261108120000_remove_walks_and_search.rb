# StepsFrom goes back to waterfront measurements only: the walk network,
# landmarks, walks, on-demand measuring of searched places and the walking
# limit setting are gone. Destinations created for a search are deleted with
# their properties (verifications, listings and quotes go with them; logged
# outbound clicks keep their row without the property). Curated destinations
# and their properties stay.
class RemoveWalksAndSearch < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM properties WHERE destination_id IN (SELECT id FROM destinations WHERE on_demand)"

    drop_table :property_walks
    drop_table :landmarks
    drop_table :walk_edges
    drop_table :walk_vertices
    drop_table :map_areas
    drop_table :site_settings

    execute "DELETE FROM destinations WHERE on_demand"
    remove_column :destinations, :on_demand

    disable_extension "pgrouting"
    disable_extension "pg_trgm"
    disable_extension "unaccent"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
