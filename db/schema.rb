# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_04_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "postgis"
  enable_extension "pg_trgm"
  enable_extension "pgrouting"
  enable_extension "unaccent"

  create_table "beaches", force: :cascade do |t|
    t.string "osm_type", null: false
    t.bigint "osm_id", null: false
    t.string "name"
    t.string "surface"
    t.geography "geom", limit: {:srid=>4326, :type=>"st_polygon", :geographic=>true}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "seen_at"
    t.index ["geom"], name: "index_beaches_on_geom", using: :gist
    t.index ["osm_type", "osm_id"], name: "index_beaches_on_osm_type_and_osm_id", unique: true
  end

  create_table "destinations", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "country_code", limit: 2, null: false
    t.string "sea_name"
    t.text "summary"
    t.geography "area", limit: {:srid=>4326, :type=>"st_polygon", :geographic=>true}, null: false
    t.geography "center", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}, null: false
    t.integer "zoom", default: 12, null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "on_demand", default: false, null: false
    t.index ["area"], name: "index_destinations_on_area", using: :gist
    t.index ["slug"], name: "index_destinations_on_slug", unique: true
  end

  create_table "import_runs", force: :cascade do |t|
    t.bigint "destination_id", null: false
    t.string "source", default: "osm", null: false
    t.string "status", default: "queued", null: false
    t.string "step"
    t.integer "steps_done", default: 0, null: false
    t.integer "steps_total"
    t.integer "attempts", default: 0, null: false
    t.jsonb "counts", default: {}, null: false
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["destination_id", "created_at"], name: "index_import_runs_on_destination_id_and_created_at"
    t.index ["status"], name: "index_import_runs_on_status"
  end

  create_table "landmarks", force: :cascade do |t|
    t.bigint "destination_id", null: false
    t.string "osm_type", null: false
    t.bigint "osm_id", null: false
    t.string "kind", null: false
    t.string "name"
    t.string "local_name"
    t.string "slug", null: false
    t.jsonb "names", default: {}, null: false
    t.text "search_text", default: "", null: false
    t.string "wikidata"
    t.integer "prominence", default: 0, null: false
    t.geography "geom", limit: {:srid=>4326, :type=>"geometry", :geographic=>true}, null: false
    t.datetime "seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "import", null: false
    t.datetime "measured_at"
    t.datetime "measure_requested_at"
    t.datetime "measure_failed_at"
    t.datetime "searched_at"
    t.index ["destination_id", "kind"], name: "index_landmarks_on_destination_id_and_kind"
    t.index ["destination_id", "osm_type", "osm_id"], name: "index_landmarks_on_destination_id_and_osm_type_and_osm_id", unique: true
    t.index ["geom"], name: "index_landmarks_on_geom", using: :gist
    t.index ["osm_type", "osm_id"], name: "index_landmarks_on_osm_type_and_osm_id"
    t.index ["search_text"], name: "index_landmarks_on_search_text", opclass: :gin_trgm_ops, using: :gin
    t.index ["slug"], name: "index_landmarks_on_slug", unique: true
  end

  create_table "listings", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.string "provider", null: false
    t.string "url", null: false
    t.string "external_id"
    t.geography "reported_lonlat", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}
    t.boolean "claims_beachfront"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id", "provider"], name: "index_listings_on_property_id_and_provider", unique: true
    t.index ["property_id"], name: "index_listings_on_property_id"
  end

  create_table "map_areas", force: :cascade do |t|
    t.geography "geom", limit: {:srid=>4326, :type=>"st_polygon", :geographic=>true}, null: false
    t.datetime "fetched_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["geom"], name: "index_map_areas_on_geom", using: :gist
  end

  create_table "outbound_clicks", force: :cascade do |t|
    t.bigint "listing_id"
    t.bigint "property_id"
    t.string "provider", null: false
    t.date "check_in"
    t.date "check_out"
    t.integer "adults"
    t.string "source_path"
    t.datetime "created_at", null: false
    t.integer "children"
    t.index ["created_at"], name: "index_outbound_clicks_on_created_at"
    t.index ["listing_id"], name: "index_outbound_clicks_on_listing_id"
    t.index ["property_id"], name: "index_outbound_clicks_on_property_id"
  end

  create_table "price_quotes", force: :cascade do |t|
    t.bigint "listing_id", null: false
    t.date "check_in", null: false
    t.date "check_out", null: false
    t.integer "adults", null: false
    t.integer "total_cents", null: false
    t.string "currency", limit: 3, default: "EUR", null: false
    t.string "source", null: false
    t.datetime "fetched_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "child_ages", default: [], null: false, array: true
    t.index ["expires_at"], name: "index_price_quotes_on_expires_at"
    t.index ["listing_id", "check_in", "check_out", "adults", "child_ages"], name: "index_price_quotes_on_listing_and_stay", unique: true
  end

  create_table "properties", force: :cascade do |t|
    t.bigint "destination_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "kind", default: "hotel", null: false
    t.integer "stars"
    t.string "address"
    t.string "website"
    t.string "osm_type"
    t.bigint "osm_id"
    t.geography "lonlat", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}, null: false
    t.geography "footprint", limit: {:srid=>4326, :type=>"st_polygon", :geographic=>true}
    t.integer "coord_mismatch_m"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "osm_missing_since"
    t.datetime "hidden_at"
    t.datetime "reviewed_at"
    t.index ["destination_id"], name: "index_properties_on_destination_id"
    t.index ["footprint"], name: "index_properties_on_footprint", using: :gist
    t.index ["lonlat"], name: "index_properties_on_lonlat", using: :gist
    t.index ["osm_type", "osm_id"], name: "index_properties_on_osm_type_and_osm_id", unique: true, where: "(osm_id IS NOT NULL)"
    t.index ["slug"], name: "index_properties_on_slug", unique: true
  end

  create_table "property_walks", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.bigint "landmark_id", null: false
    t.integer "walk_m", null: false
    t.integer "busy_crossings", default: 0, null: false
    t.integer "stairs", default: 0, null: false
    t.datetime "measured_at", null: false
    t.index ["landmark_id", "walk_m"], name: "index_property_walks_on_landmark_id_and_walk_m"
    t.index ["property_id", "landmark_id"], name: "index_property_walks_on_property_id_and_landmark_id", unique: true
  end

  create_table "road_segments", force: :cascade do |t|
    t.bigint "osm_id", null: false
    t.string "category", null: false
    t.string "highway"
    t.string "name"
    t.geography "geom", limit: {:srid=>4326, :type=>"line_string", :geographic=>true}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "seen_at"
    t.index ["geom"], name: "index_road_segments_on_geom", using: :gist
    t.index ["osm_id"], name: "index_road_segments_on_osm_id", unique: true
  end

  create_table "verifications", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.string "type", null: false
    t.string "subject", default: "", null: false
    t.string "category", default: "unknown", null: false
    t.integer "distance_m"
    t.jsonb "evidence", default: {}, null: false
    t.datetime "measured_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id", "type", "subject"], name: "index_verifications_on_property_id_and_type_and_subject", unique: true
    t.index ["type", "category"], name: "index_verifications_on_type_and_category"
  end

  create_table "walk_edges", force: :cascade do |t|
    t.bigint "osm_way_id", null: false
    t.bigint "source", null: false
    t.bigint "target", null: false
    t.string "highway", null: false
    t.boolean "steps", default: false, null: false
    t.boolean "busy", default: false, null: false
    t.float "length_m", default: 0.0, null: false
    t.geography "geom", limit: {:srid=>4326, :type=>"line_string", :geographic=>true}, null: false
    t.datetime "seen_at"
    t.index ["geom"], name: "index_walk_edges_on_geom", using: :gist
    t.index ["osm_way_id"], name: "index_walk_edges_on_osm_way_id"
  end

  create_table "walk_vertices", force: :cascade do |t|
    t.bigint "node_id", null: false
    t.boolean "busy", default: false, null: false
    t.geography "geom", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}, null: false
    t.datetime "seen_at"
    t.index ["geom"], name: "index_walk_vertices_on_geom", using: :gist
    t.index ["node_id"], name: "index_walk_vertices_on_node_id", unique: true
  end

  create_table "water_features", force: :cascade do |t|
    t.string "osm_type", null: false
    t.bigint "osm_id", null: false
    t.string "kind", null: false
    t.string "name"
    t.geography "geom", limit: {:srid=>4326, :type=>"geometry", :geographic=>true}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "seen_at"
    t.index ["geom"], name: "index_water_features_on_geom", using: :gist
    t.index ["osm_type", "osm_id"], name: "index_water_features_on_osm_type_and_osm_id", unique: true
  end

  add_foreign_key "import_runs", "destinations", on_delete: :cascade
  add_foreign_key "landmarks", "destinations"
  add_foreign_key "listings", "properties", on_delete: :cascade
  add_foreign_key "outbound_clicks", "listings", on_delete: :nullify
  add_foreign_key "outbound_clicks", "properties", on_delete: :nullify
  add_foreign_key "price_quotes", "listings", on_delete: :cascade
  add_foreign_key "properties", "destinations"
  add_foreign_key "property_walks", "landmarks", on_delete: :cascade
  add_foreign_key "property_walks", "properties", on_delete: :cascade
  add_foreign_key "verifications", "properties", on_delete: :cascade
end
