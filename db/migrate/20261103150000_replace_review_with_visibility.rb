# Properties are listed automatically once measured; a person no longer
# approves each result. An admin can still hide a property (what rejecting
# did), and a property an admin has edited or hidden keeps its details on
# re-import (what any review did).
class ReplaceReviewWithVisibility < ActiveRecord::Migration[8.1]
  def up
    add_column :properties, :hidden_at, :datetime
    add_column :properties, :reviewed_at, :datetime

    execute <<~SQL
      UPDATE properties SET reviewed_at = v.updated_at,
                            hidden_at = CASE WHEN v.qa_status = 'rejected' THEN v.updated_at END
      FROM verifications v
      WHERE v.property_id = properties.id AND v.qa_status <> 'pending'
    SQL

    remove_index :verifications, :qa_status
    remove_column :verifications, :qa_status
    remove_column :verifications, :qa_note
  end

  def down
    add_column :verifications, :qa_status, :string, null: false, default: "pending"
    add_column :verifications, :qa_note, :text
    add_index :verifications, :qa_status

    execute <<~SQL
      UPDATE verifications SET qa_status = CASE WHEN p.hidden_at IS NOT NULL THEN 'rejected' ELSE 'approved' END
      FROM properties p
      WHERE p.id = verifications.property_id AND p.reviewed_at IS NOT NULL
    SQL

    remove_column :properties, :reviewed_at
    remove_column :properties, :hidden_at
  end
end
