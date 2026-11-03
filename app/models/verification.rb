# A measured attribute of a property, such as being on the waterfront. Each
# subclass (see app/models/verifications/) defines its categories, which of
# them are shown publicly, and what its evidence holds.
class Verification < ApplicationRecord
  CATEGORIES = %w[unknown].freeze
  LISTED_CATEGORIES = [].freeze

  belongs_to :property

  validates :type, uniqueness: { scope: %i[property_id subject] }
  validates :distance_m, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Results in a category that may be shown to visitors.
  def self.listed
    where(category: self::LISTED_CATEGORIES)
  end

  # Key used for translations and CSS, e.g. "waterfront".
  def self.key
    name.demodulize.underscore
  end

  def listed?
    category.in?(self.class::LISTED_CATEGORIES)
  end
end
