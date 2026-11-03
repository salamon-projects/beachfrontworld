# How far a property is from a landmark on foot (see Walks::Measurement).
class PropertyWalk < ApplicationRecord
  belongs_to :property
  belongs_to :landmark

  def minutes = Walks.minutes(walk_m)

  def steps = Walks.steps(walk_m)
end
