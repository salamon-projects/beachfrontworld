# Result of the weekly check of each property's website (Websites::Checker):
# a link that leads nowhere is not shown on the site.
class AddWebsiteCheckToProperties < ActiveRecord::Migration[8.1]
  def change
    add_column :properties, :website_checked_at, :datetime
    add_column :properties, :website_status, :string
    add_column :properties, :website_failures, :integer, null: false, default: 0
    add_column :properties, :website_broken_at, :datetime
  end
end
