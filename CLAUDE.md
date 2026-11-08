# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

StepsFrom lists holiday properties that are **measured** (in PostGIS, against OpenStreetMap data) as truly beachfront. Nothing is hand-reviewed: a property measured in a listed category is on the site automatically; admins can only edit or hide it. (A walking-distance-to-landmarks version with pgRouting and LLM search existed in November 2026 and was removed as too costly to run; migration `20261108120000_remove_walks_and_search` dropped its tables.) README.md is detailed and current; read it for setup, admin workflow, affiliate/price configuration and deployment.

## Commands

```bash
bin/dev                                   # Rails server + Sass watcher, http://localhost:3000 (admin: /admin, admin/admin)
bin/rails db:setup                        # create DBs, load schema, seed (dev seeds include fictional "Demo Bay")
bundle exec rspec                         # all specs (need PostgreSQL + PostGIS)
bundle exec rspec spec/services/waterfront/classifier_spec.rb:42   # single file / example
bin/rubocop                               # rubocop-rails-omakase style
bin/brakeman && bin/bundler-audit         # security checks run in CI
bin/ci                                    # local CI: setup, rubocop, bundler-audit, brakeman (not the specs)
bin/rails osm:import[makarska-riviera]    # import + measure one destination (osm:import_all for all)
bin/rails waterfront:classify[makarska-riviera]   # re-measure without re-importing
```

CI runs `bin/rails dartsass:build` before the specs; do the same if a request spec fails on a missing stylesheet. DB connection comes from `DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASSWORD` or a `postgis://` `DATABASE_URL`. Any PostGIS 3 image works; production and CI run `pgrouting/pgrouting:16-3.5-3.8.0` (PostGIS plus an unused pgRouting), and changing the image in `config/deploy.yml` needs the Deploy workflow's `db-upgrade` command (`kamal accessory reboot db`). `bin/bundler-audit` in CI uses the latest advisory database, so it can fail on an unchanged commit when a gem (e.g. Rails) gets a security release — update the gem.

Every push to `main` deploys to production (Kamal) once CI passes — a green commit on main is a release.

## Stack constraints

Rails 8.1, Ruby 3.3, HAML views, SCSS via dartsass-rails, Propshaft. Server-rendered only: **no Hotwire, Stimulus or importmap**. JavaScript is limited to small plain scripts in `app/assets/javascripts/` (`map.js` draws Leaflet maps from vendored `vendor/assets/leaflet`; `filters.js` and `stay_fields.js` — range calendar and guest steppers over `shared/_stay_fields` — are progressive enhancement). Pages must work without JS, and the enhanced fields must submit the same params as the plain ones. Solid Queue / Solid Cache for jobs and cache.

The CSP (`config/initializers/content_security_policy.rb`) allows only same-origin scripts, styles and fonts and no inline `style` attributes: fonts are self-hosted in `app/assets/fonts`, and data-driven positions are drawn as inline SVG attributes (e.g. `shared/_distance_ruler`). Design tokens live in `_variables.scss`; the coral `$measure` colour is reserved for measurements (ocean blues and `$ocean-gradient` carry the brand).

Project principles (from README): no scraping — property/map data only from OSM, prices and links only from official affiliate programmes/APIs. A booking site's "beachfront" label is a hint used to flag conflicts, never to list a property.

## Architecture

**Data flow:** `Destination` (bounding box) → OSM import → geometry tables (`WaterFeature`, `Beach`, `RoadSegment`) + `Property` → measurement → `Verifications::Waterfront` → listed automatically (`Property.published`) → destination page → property page with `Listing`s/prices.

- **OSM import** (`app/services/osm/`): `Osm::DestinationImport` runs one importer per layer (`Importers::Coastline`, `InlandWater`, `Beaches`, `Roads`, `Accommodations`, all `< Importers::Base`) through `OverpassClient` (retries across public Overpass instances; `OVERPASS_URLS` overrides), then re-measures every property. `OsmImportJob` wraps it and records progress/outcome in an `ImportRun` (shown in admin). Re-imports remove map features OSM no longer returns but never delete properties — those get `osm_missing_since` set (scope `missing_from_osm`). Properties an admin edited or hid (`reviewed_at`) keep their name/position/details; others follow OSM.
- **Measurement** (`app/services/waterfront/`): `Measurer` does the PostGIS queries (distance to water, road/promenade crossing, nearest beach, booking-site coordinate mismatch) → `Measurement`; `Classifier` maps it to a category using thresholds in `config/waterfront.yml`; `Classification` orchestrates and saves the result. `ClassifyPropertyJob` runs it after a property moves. If you change thresholds, keep the public "How we verify" page (`app/views/pages/how_we_verify.html.haml`) accurate — it is a ranking-transparency requirement.
- **Verifications** are STI rows in `verifications` (`Verification` base, `Verifications::Waterfront`) holding category, `distance_m` and JSON `evidence` (via `store_accessor`). Properties hold location data plus `hidden_at`/`reviewed_at`. `Property.published`: not hidden, not missing from OSM, and a waterfront result in `LISTED_CATEGORIES`. README describes how to add a new verified attribute.
- **Geometry:** SRID 4326 geographic types via `activerecord-postgis-adapter`; build values with the `Geo` helpers (`app/models/geo.rb`, coordinates are `[lon, lat]`).
- **Public search:** `Stay` (ActiveModel: dates + adults/children from params) and `PropertySearch` (filters + ordering; price sort when a valid stay is given, else by waterfront) feed destination pages. `Offer` (a `Data` value) pairs each active `Listing` with a fresh `PriceQuote`, cheapest first, marking the best.
- **Affiliate/prices:** outbound buttons go through `/go/:listing_id` (`OutboundController` logs an `OutboundClick` without IP, `Affiliate::LinkBuilder` applies `config/affiliates.yml` + `*_TRACKING_URL` templates). Prices come from `Prices::Provider` subclasses in `app/services/prices/providers/` selected by `PRICE_PROVIDERS`; only `fake` exists (dev only, refuses production). `RefreshPricesJob`/`Prices::Refresher` cache quotes in `price_quotes`.
- **SEO:** `SeoHelper` builds schema.org JSON-LD (WebSite on home, BreadcrumbList + ItemList on destinations, Hotel/LodgingBusiness on properties) and the layout adds Open Graph tags with `public/og-image.jpg`. Pages with stay or filter params are `noindex`; others get a canonical URL without a trailing slash.
- **Admin** (`app/controllers/admin/`, layout `admin`) uses a session-based login from `ADMIN_USER`/`ADMIN_PASSWORD`. Recurring production jobs (weekly OSM refresh, weekly website check, quote purge) are in `config/recurring.yml`. `CheckWebsitesJob`/`Websites::Checker` hide an "Official website" link that leads nowhere (`website_broken_at`); it only fetches public addresses.

## Tests

RSpec + FactoryBot + Capybara (rack_test) + WebMock (no outbound network). OSM import specs use `FakeOverpassClient` (`spec/support/`) serving `spec/fixtures/files/overpass/sample_bay.json`, grouped by layer — pass it as `client:`. Geometry factories are in `spec/factories/geo_features.rb`; `spec/support/geo_helpers.rb` and `admin_helpers.rb` provide shared helpers.
