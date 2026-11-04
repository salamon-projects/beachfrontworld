# Settings an admin changes on the site (one row; see SiteSetting).
class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings do |t|
      # How far a walk may be for a stay to count as near a place.
      t.integer :max_walk_m, null: false, default: 1000
      t.timestamps
    end
  end
end
