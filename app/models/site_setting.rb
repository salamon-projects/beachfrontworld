# Settings an admin changes in /admin/settings, kept in one row.
class SiteSetting < ApplicationRecord
  MAX_WALK_RANGE = 300..3000

  validates :max_walk_m, numericality: { only_integer: true, in: MAX_WALK_RANGE }

  after_commit { Walks.reset_max_walk_m! }

  def self.current
    first || create!(max_walk_m: Walks.config.fetch(:default_max_walk_m))
  end
end
