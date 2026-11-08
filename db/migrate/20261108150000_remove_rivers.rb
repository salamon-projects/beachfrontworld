# A riverbank is not a beach: rivers are no longer imported as water. Deletes
# the river areas already imported and re-measures the properties that were
# measured against one, so they are classified against the sea or a lake.
class RemoveRivers < ActiveRecord::Migration[8.1]
  def up
    property_ids = select_values(<<~SQL)
      SELECT property_id FROM verifications
      WHERE type = 'Verifications::Waterfront' AND evidence->>'water_kind' = 'river'
    SQL
    execute "DELETE FROM water_features WHERE kind = 'river'"

    Property.where(id: property_ids).find_each { |property| Waterfront::Classification.new(property).call }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
