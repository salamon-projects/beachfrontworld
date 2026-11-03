# Places visitors want to stay near (sights, squares, pedestrian streets,
# parks, beaches, stations), imported from OSM per destination.
class CreateLandmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :landmarks do |t|
      t.references :destination, null: false, foreign_key: true, index: false
      t.string :osm_type, null: false
      t.bigint :osm_id, null: false
      t.string :kind, null: false
      # English name when OSM has one, else the local name; nil for unnamed
      # beaches, which are only found by kind.
      t.string :name
      t.string :local_name
      t.string :slug, null: false
      # Every name:* tag, so a search in any language finds it.
      t.jsonb :names, null: false, default: {}
      # The names lowercased, without accents, for trigram search.
      t.text :search_text, null: false, default: ""
      t.string :wikidata
      t.integer :prominence, null: false, default: 0
      t.geometry :geom, geographic: true, srid: 4326, null: false
      t.datetime :seen_at
      t.timestamps
      t.index %i[destination_id osm_type osm_id], unique: true
      t.index :slug, unique: true
      t.index %i[destination_id kind]
      t.index :geom, using: :gist
      t.index :search_text, using: :gin, opclass: :gin_trgm_ops
    end
  end
end
