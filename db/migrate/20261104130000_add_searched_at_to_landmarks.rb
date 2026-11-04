# When a visitor last searched for a landmark: its page is shown even in a
# destination not published yet (Landmark.visible), whether it was found for
# the search or imported with the destination.
class AddSearchedAtToLandmarks < ActiveRecord::Migration[8.1]
  def up
    add_column :landmarks, :searched_at, :datetime
    execute "UPDATE landmarks SET searched_at = created_at WHERE source = 'search'"
  end

  def down
    remove_column :landmarks, :searched_at
  end
end
