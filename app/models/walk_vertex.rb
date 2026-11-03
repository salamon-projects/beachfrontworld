# A junction or end point of the walk network; node_id is the OSM node id
# that WalkEdge#source and #target refer to.
class WalkVertex < ApplicationRecord
  belongs_to :destination
end
