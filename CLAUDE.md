# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

StepsFrom lists holiday stays by the **measured walk** (pgRouting over OpenStreetMap streets and paths) to what the visitor wants to be near — a landmark typed in free text (looked up and measured on demand when we do not have it yet), a kind of place such as a beach, or the most sights within 15 minutes — plus an automatic waterfront badge on the coast. Nothing is hand-reviewed; admins can only hide properties. README.md is detailed and current; read it for setup, admin workflow, affiliate/price configuration and deployment.

## Commands

```bash
bin/dev                                   # Rails server + Sass watcher, http://localhost:3000 (admin: /admin, admin/admin)
bin/rails db:setup                        # create DBs, load schema, seed (dev seeds include fictional "Demo Bay")
bundle exec rspec                         # all specs (need PostgreSQL + PostGIS)
bundle exec rspec spec/services/waterfront/classifier_spec.rb:42   # single file / example
bin/rubocop                               # rubocop-rails-omakase style
bin/brakeman && bin/bundler-audit         # security checks run in CI
bin/rails osm:import[makarska-riviera]    # import + measure one destination (osm:import_all for all)
bin/rails waterfront:classify[makarska-riviera]   # re-measure waterfront without re-importing
bin/rails walks:measure[makarska-riviera]         # re-measure walks without re-importing
```

CI runs `bin/rails dartsass:build` before the specs; do the same if a request spec fails on a missing stylesheet. DB connection comes from `DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASSWORD` or a `postgis://` `DATABASE_URL`. The database needs PostGIS **and pgRouting**, pg_trgm and unaccent — locally the `pgrouting/pgrouting:16-3.5-3.8.0` image (README). `db/schema.rb` lists `postgis` before `pgrouting` thanks to `config/initializers/schema_extensions_order.rb`; keep it that way or `db:schema:load` fails.

Every push to `main` deploys to production (Kamal) once CI passes — a green commit on main is a release. Changing the database image in `config/deploy.yml` needs the Deploy workflow's `db-upgrade` command (`kamal accessory reboot db`) before the app can boot on it.

## Stack constraints

Rails 8.1, Ruby 3.3, HAML views, SCSS via dartsass-rails, Propshaft. Server-rendered only: **no Hotwire, Stimulus or importmap**. JavaScript is limited to small plain scripts in `app/assets/javascripts/` (`map.js` draws Leaflet maps from vendored `vendor/assets/leaflet`; `filters.js` and `stay_fields.js` — range calendar and guest steppers over `shared/_stay_fields` — are progressive enhancement). Pages must work without JS, and the enhanced fields must submit the same params as the plain ones. Solid Queue / Solid Cache for jobs and cache.

The CSP (`config/initializers/content_security_policy.rb`) allows only same-origin scripts, styles and fonts and no inline `style` attributes: fonts are self-hosted in `app/assets/fonts`, and data-driven positions are drawn as inline SVG attributes (e.g. `shared/_distance_ruler`). Design tokens live in `_variables.scss`; the orange `$measure` colour is reserved for measurements.

Project principles (from README): no scraping — property/map data only from OSM, prices and links only from official affiliate programmes/APIs. A booking site's "beachfront" label is a hint used to flag conflicts, never to list a property.

## Architecture

**Data flow:** `Destination` (bounding box) → OSM import → geometry tables (`WaterFeature`, `Beach`, `RoadSegment`, `WalkEdge`/`WalkVertex`) + `Landmark` + `Property` → measurement (`Verifications::Waterfront`, `PropertyWalk`) → listed automatically → search (`/search?q=`) → landmark page (`/near/:slug`) / destination page → property page with `Listing`s/prices. On demand: search → `Search::Locator` (Nominatim) → `Landmark` with `source: "search"` → its page waits ("Measuring…", meta refresh) while `MeasureLandmarkJob` fetches the area around it (`Osm::AreaImport`, skipped when `MapArea` covers it fresh) and measures it; `MeasureAreaJob` adds the waterfront and walks to other nearby landmarks afterwards.

- **OSM import** (`app/services/osm/`): `Osm::DestinationImport` runs one importer per layer (`Importers::Coastline`, `InlandWater`, `Beaches`, `Roads`, `WalkNetwork` (fetched in tiles, rebuilt each time), `Landmarks`, `Accommodations`, all `< Importers::Base`) through `OverpassClient` (retries across public Overpass instances; `OVERPASS_URLS` overrides), then re-measures every property. `OsmImportJob` wraps it and records progress/outcome in an `ImportRun` (shown in admin). Importers take a `bbox:` (default the destination's) so `Osm::AreaImport` can reuse them for one searched place. The walk network is global (no `destination_id`), one edge per consecutive node pair, so boxes fetched separately join up. Imports set `Property#skip_measurement` and measure all properties together afterwards — do not let them enqueue `ClassifyPropertyJob` per property. Re-imports remove map features OSM no longer returns but never delete properties — those get `osm_missing_since` set (scope `missing_from_osm`) and leave the site. Properties an admin edited or hid (`reviewed_at`) keep their name/position/details; others follow OSM.
- **Measurement** (`app/services/waterfront/`): `Measurer` does the PostGIS queries (distance to water, road/promenade crossing, nearest beach, booking-site coordinate mismatch) → `Measurement`; `Classifier` maps it to a category using thresholds in `config/waterfront.yml`; `Classification` orchestrates and saves the result. `ClassifyPropertyJob` re-measures waterfront and walks after a property moves. If you change thresholds (`config/waterfront.yml`, `config/walks.yml`) or ranking, keep the public "How we measure and rank" page (`app/views/pages/how_we_verify.html.haml`) accurate — it is a ranking-transparency requirement.
- **Walks** (`app/services/walks/`): `Measurement.new(landmarks)` runs one `pgr_drivingDistance` tree per landmark from a virtual root (`Walks::Network::ROOT`, joined by virtual edges to where the landmark meets the network) and stores each property's walk, busy-road crossings and stairs in `property_walks` via SQL (temp tables `walk_snaps`/`walk_tree`); `Route` traces one walk with `pgr_dijkstra` for the map. Minutes/steps are derived (`Walks.minutes`/`.steps`), never stored. The walking limit is `Walks.max_walk_m` (admin-set `SiteSetting`, cached per process for 30 s, default `default_max_walk_m` in `config/walks.yml`): filter listed walks with `PropertyWalk.within_reach`, and pass `Walks.measurement_config` (not `Walks.config`) where a measurement needs the limit.
- **Search** (`app/services/search/`): `Interpreter` asks an OpenAI-compatible LLM (`LLM_API_KEY`, default Tensorix) to turn free text into places/kinds/limits, returning nil on any failure; `Resolver` matches names with `Landmark.search` (pg_trgm on accent-free `search_text` built from every `name:*` tag) and decides the outcome (landmark, choices, locate, kind, destination, none); `:locate` goes to `Locator`. Searched landmarks are visible even in an unpublished destination (`Landmark.visible`). WebMock blocks the LLM and Nominatim in specs — stub them or inject the interpreter/nominatim.
- **Verifications** are STI rows in `verifications` (`Verification` base, `Verifications::Waterfront`) holding category, `distance_m` and JSON `evidence` (via `store_accessor`). Properties hold only location data. `Property.published`: not hidden, not missing from OSM, and has a `PropertyWalk` or a waterfront result in `LISTED_CATEGORIES`. README describes how to add a new verified attribute.
- **Geometry:** SRID 4326 geographic types via `activerecord-postgis-adapter`; build values with the `Geo` helpers (`app/models/geo.rb`, coordinates are `[lon, lat]`).
- **Listing pages:** `Stay` (ActiveModel: dates + guests from params) and `PropertySearch` (target = one landmark or `near` kind; filters `max_minutes`, `quiet`, `kind`; price sort with a valid stay, else by walk, or by `nearby_count` without a target) feed destination and landmark pages through `ApplicationController#list` and `shared/_listing`. `Offer` (a `Data` value) pairs each active `Listing` with a fresh `PriceQuote`, cheapest first, marking the best.
- **Affiliate/prices:** outbound buttons go through `/go/:listing_id` (`OutboundController` logs an `OutboundClick` without IP, `Affiliate::LinkBuilder` applies `config/affiliates.yml` + `*_TRACKING_URL` templates). Prices come from `Prices::Provider` subclasses in `app/services/prices/providers/` selected by `PRICE_PROVIDERS`; only `fake` exists (dev only, refuses production). `RefreshPricesJob`/`Prices::Refresher` cache quotes in `price_quotes`.
- **Admin** (`app/controllers/admin/`, layout `admin`) uses a session-based login from `ADMIN_USER`/`ADMIN_PASSWORD`. Recurring production jobs (weekly OSM refresh, quote purge) are in `config/recurring.yml`.

## Tests

RSpec + FactoryBot + Capybara (rack_test) + WebMock (no outbound network). OSM import specs use `FakeOverpassClient` (`spec/support/`) serving `spec/fixtures/files/overpass/sample_bay.json`, grouped by layer (matched by a selector substring, checked in order) — pass it as `client:`. The fixture's walk network and landmarks have hand-computed walks in `spec/services/walks/measurement_spec.rb`. Geometry factories are in `spec/factories/geo_features.rb`; `spec/support/geo_helpers.rb` and `admin_helpers.rb` provide shared helpers.
