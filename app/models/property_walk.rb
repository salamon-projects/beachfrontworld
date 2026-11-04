# How far a property is from a landmark on foot (see Walks::Measurement).
class PropertyWalk < ApplicationRecord
  belongs_to :property
  belongs_to :landmark

  # Walks within the current limit (Walks.max_walk_m): shortening it hides
  # longer walks measured before, without measuring again.
  scope :within_reach, -> { where(walk_m: ..Walks.max_walk_m) }

  def minutes = Walks.minutes(walk_m)

  def steps = Walks.steps(walk_m)
end
