# Walking distance from each property to the landmarks around it, measured
# along the walk network by Walks::Measurement.
class CreatePropertyWalks < ActiveRecord::Migration[8.1]
  def change
    create_table :property_walks do |t|
      t.references :property, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :landmark, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :walk_m, null: false
      # Primary, secondary or trunk roads crossed on the way.
      t.integer :busy_crossings, null: false, default: 0
      # Flights of steps on the way.
      t.integer :stairs, null: false, default: 0
      t.datetime :measured_at, null: false
      t.index %i[property_id landmark_id], unique: true
      t.index %i[landmark_id walk_m]
    end
  end
end
