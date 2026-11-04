# StepsFrom

Stays steps from what you came for.

Visitors type what they want to stay close to — "Eiffel Tower", "La Rambla", "a beach
in Makarska", in any language — and [StepsFrom](https://stepsfrom.com) lists the stays
nearby, ordered by the **walk we measured**: along the streets and paths of
OpenStreetMap, not in a straight line, with the minutes, the steps, the busy roads to
cross and the flights of steps on the way. On the coast it also measures how far the
water is and whether a road lies in between. Each stay links to the booking sites
that carry it, with the cheapest one first once prices are available.

Booking sites quote straight-line distances ("0.4 km from the centre") or loose
labels ("near the beach"); measuring the walk itself is what sets StepsFrom apart.

Principles:

- **No scraping.** Property and map data come from OpenStreetMap (ODbL). Booking-site
  links and prices come only from official affiliate programmes and APIs.
- **The measurement decides.** Everything is measured automatically and listed when it
  is within walking distance of a landmark or on the waterfront. A booking site's
  "beachfront" label is stored as a hint and used to flag conflicts, never to list a
  property.

## Stack

Ruby 3.3, Rails 8.1, PostgreSQL 16 + PostGIS 3 (`activerecord-postgis-adapter`) + pgRouting 3,
HAML, SCSS (`dartsass-rails`), Propshaft. Pages are rendered on the server, with no
Hotwire, Stimulus or importmap. The only JavaScript is `app/assets/javascripts/map.js`,
which draws the maps with Leaflet 1.9.4 (vendored in `vendor/assets/leaflet`, BSD-2).
Background jobs and cache run on Solid Queue and Solid Cache. Tests use RSpec.

## Setup

You need PostgreSQL with the PostGIS, pgRouting, pg_trgm and unaccent extensions, e.g.
`apt install postgresql-16-postgis-3 postgresql-16-pgrouting`, or the same image as
production:

```bash
docker run -d --name stepsfrom-db -e POSTGRES_PASSWORD=postgres -p 127.0.0.1:5435:5432 \
  pgrouting/pgrouting:16-3.5-3.8.0
export DB_HOST=localhost DB_PORT=5435 DB_USER=postgres DB_PASSWORD=postgres
```

```bash
bundle install
bin/rails db:setup      # creates the databases, loads the schema and seeds
bin/dev                 # Rails server + Sass watcher on http://localhost:3000
```

In development the seeds also load **Demo Bay**, a fictional bay with sample
properties and made-up prices, so you can try the site without importing any data.
The admin is at `/admin`; in development and test it accepts `admin` / `admin`.

The database connection reads `DB_HOST`, `DB_PORT`, `DB_USER` and `DB_PASSWORD`, or a
`DATABASE_URL` with the `postgis://` scheme.

## Workflow

1. **Destination.** The seeded launch destinations are Makarska Riviera, Poreč, Hvar,
   Kassandra, Chania coast, Rhodes east coast, Paris and Barcelona. They start
   unpublished. Add or adjust destinations in the admin by bounding box; keep city
   boxes to the central districts.
2. **Import.** Fetch coastline, lakes, beaches, roads, the walk network, landmarks and
   accommodation from the Overpass API, then measure every property (waterfront and
   walks). Run it with "Import from OSM" in the admin, or with:
   ```bash
   bin/rails osm:import[makarska-riviera]
   bin/rails osm:import_all
   ```
   Busy Overpass servers are retried with backoff across several public
   instances; `OVERPASS_URLS` (comma-separated) replaces the list. In production a weekly
   refresh is scheduled (`config/recurring.yml`). The admin's Destinations page shows
   each import's current step, or how it ended (counts or the error), and refreshes
   itself while one runs; "Imports" lists the history.

   Running an import again updates what is there. Map features (coastline,
   lakes, beaches, roads, landmarks) that OSM no longer returns inside the bounding
   box are removed, so measurements always use the current map (features within
   about 100 m of the box's edge are kept, and a layer that comes back empty removes
   nothing); the same goes for the walk network. Properties are never deleted: one that OSM
   no longer returns is taken off the site and listed under "Not in OSM" in the
   admin. Until an admin edits or hides a property, its name, position and details
   follow OSM.
3. **Check.** Properties are listed automatically once measured. The admin shows
   what is "On the site", what has "Nothing nearby" and what is hidden; hide a
   property that is closed or not a real accommodation, and correct coordinates
   where needed (which measures it again). Edited and hidden properties keep their
   name, position and details on later imports. "OTA claim conflicts" lists
   properties that a booking site calls beachfront but that we measured further away.
4. **Listings.** On each property, add its page on Booking.com, Expedia, Hotels.com,
   Vrbo, Agoda or Trip.com. Optionally enter the position the site shows. If it is
   more than 150 m from ours, the property is flagged.
5. **Publish** the destination.

To re-measure without re-importing:

```bash
bin/rails waterfront:classify[makarska-riviera]
bin/rails walks:measure[makarska-riviera]
```

## Searching

The home page asks what you want to stay close to. `Search::Interpreter` sends only
that text to a language model behind an OpenAI-compatible chat completions API
(Tensorix by default, set with `LLM_API_KEY`; `LLM_BASE_URL` and `LLM_MODEL` select
another provider or model) and gets back the place meant, named landmarks in English
and the local language, kinds of place ("a beach"), a walking limit and a kind of
stay. Answers are cached for 30 days. Without a key, or when the call fails, landmark
names are matched against the words of the text directly.

`Search::Resolver` matches the names with trigrams against every `name:*` tag of the
landmarks we have (`Landmark.search`), then sends the visitor to the landmark's page
(`/near/:slug`), to a destination ordered by the walk to the nearest landmark of a
kind (`?near=beach`), to a destination, or to a page of choices.

A place we do not have yet (or one in a town that none of our destinations is named
after) is **measured on demand**. `Search::Locator` looks it up with Nominatim,
OpenStreetMap's own search (`Osm::Nominatim`: one request a second, answers cached
for 30 days, `NOMINATIM_URL` for another instance), and saves it as a landmark with
`source: "search"` — any sight, square, street, station, venue or address; a whole
town or region is refused. It goes into the destination around it, else one of the
same town, else a new `on_demand` destination for the town, which grows with each
place searched in it. Its landmark page then shows "Measuring…" and reloads itself
while `MeasureLandmarkJob` (queue `areas`, two at a time) fetches the walk network
and accommodation around it (`Osm::AreaImport#walks`, about 5.5 × 5.5 km, unless
`MapArea` says that part of the map was fetched in the last 30 days) and measures the
walks to it. On public Overpass servers this takes about one to two minutes in a
city centre, almost all of it waiting for Overpass; measuring itself takes seconds.
`MeasureAreaJob` then adds water, beaches and roads for the waterfront badge and
measures the newly imported properties against the other landmarks nearby. If
Overpass does not answer, the page offers to try again. One visitor can look up 20
new places an hour. Searched places are re-measured once their map data is 30 days
old (`config/recurring.yml`).

## How walks are measured

`Osm::Importers::WalkNetwork` imports the ways people can walk on (footways, paths,
steps, pedestrian streets and roads; not motorways, private ways or ways closed to
pedestrians) into `walk_edges`/`walk_vertices`, one edge per pair of consecutive
nodes, with OSM node ids as vertex ids. The network is one map shared by all
destinations and searched places, filled in box by box: a re-fetched way replaces its
edges, and ways inside the box that OSM no longer returns are removed. Primary,
secondary and trunk roads are marked busy.
`Osm::Importers::Landmarks` imports sights and monuments with a Wikidata or
Wikipedia entry, museums, squares, pedestrian streets (one per name), parks, beaches,
stations and markets.

`Walks::Measurement` then grows a pgRouting shortest-path tree
(`pgr_drivingDistance`) from each landmark over the network, up to 2.5 km, and stores
for every property within reach (of any destination) its walk in `property_walks`: the distance, the busy
roads crossed (rather than walked along) and the flights of steps. Minutes and steps
are derived with the pace in `config/walks.yml`. `Walks::Route` traces a walk for the
property page's map. The public "How we measure and rank" page describes the same
rules; keep it accurate when you change them.

## How properties are classified

`Waterfront::Measurer` (`app/services/waterfront/measurer.rb`) measures in PostGIS,
from the building outline when OSM has one, otherwise from the point:

- the geodesic distance to the nearest sea coastline, lake or river area;
- whether the straight line to the water crosses a road or railway (tunnels excluded)
  or a promenade/path, and whether it runs over a mapped beach;
- the nearest beach and its surface (sand, pebble or rock);
- how far the positions reported by booking sites are from ours.

`Waterfront::Classifier` turns this into a category, using the thresholds in
`config/waterfront.yml`:

| Category | Rule (defaults) |
|---|---|
| Verified beachfront (`direct`) | No road or railway in between, and water ≤ 50 m; or ≤ 150 m across a beach that starts within 20 m |
| Steps from the water (`near`) | Water ≤ 100 m |
| Short walk to the water (`walkable`) | Water ≤ 300 m |
| `not_waterfront` | Further: no waterfront badge |
| `unknown` | No water imported for the destination yet |

The public "How we measure and rank" page shows the same thresholds. It is required
for ranking transparency, so keep it accurate when you change them.

### Verified attributes

Waterfront is the first of several **verified attributes**. Each result is a
row in `verifications` (single-table inheritance): `Verifications::Waterfront`
holds the category, the headline distance (`distance_m`) and the measurement
details in `evidence`. Properties keep only location data. A property is
listed when it has a walk to a landmark or a waterfront result in a listed
category (`Property.published`).

To add an attribute, for example a verified sea view:

1. Create `app/models/verifications/sea_view.rb` (`< Verification`) with its
   `CATEGORIES`, `LISTED_CATEGORIES` and `store_accessor :evidence` keys.
   `subject` distinguishes several results of one type, for example one per
   landmark for a landmark view.
2. Write the measuring service (like `Waterfront::Classification`) that saves it.
3. Add the badge texts under `config/locales/en.yml` and show the result in the
   admin "Measurements" block and on the public pages.

## Affiliate links

Buttons go through `/go/:listing_id`. That route logs the click (provider, dates and
source page, no IP address) and redirects to the booking site with the visitor's
dates filled in (`config/affiliates.yml`). Once a programme approves the site, set
its tracking template. The template must contain `{url}`, which is replaced by the
URL-encoded target:

| Variable | Example |
|---|---|
| `BOOKING_TRACKING_URL` | CJ deep link: `https://www.anrdoezrs.net/click-<PID>-<AID>?url={url}` |
| `EXPEDIA_TRACKING_URL`, `HOTELS_COM_TRACKING_URL`, `VRBO_TRACKING_URL` | Expedia Group Travel Creator link format |
| `AGODA_TRACKING_URL`, `TRIP_COM_TRACKING_URL` | as provided by the programme |

Until a template is set, that site's buttons link directly (untracked), and the
admin shows a warning.

## Prices

Prices come from **providers** (`app/services/prices/provider.rb`). Each one wraps
an official API: a booking site's partner API or a licensed aggregator. Quotes are
cached in `price_quotes` for the provider's TTL (6 hours by default). When dates are
given, destination pages sort by the cheapest fresh quote.

No real provider exists yet: they depend on partner approval (for example Stay22,
Agoda Partners, the Booking.com Demand API or Expedia Rapid). To add one, subclass
`Prices::Provider` in `app/services/prices/providers/` and list it in
`PRICE_PROVIDERS` (comma-separated). Development uses the `fake` provider, which
returns made-up prices and refuses to run in production.

## Deploying (Kamal, Hetzner)

Production runs on one server with [Kamal](https://kamal-deploy.org): the app
container behind kamal-proxy (Let's Encrypt TLS for `stepsfrom.com` and
`www.stepsfrom.com`, www redirects to the bare domain) and a PostGIS + pgRouting container
(`stepsfrom-db`). See `config/deploy.yml`.

Deploys run from GitHub Actions (`.github/workflows/deploy.yml`): every push to
`main` deploys automatically once CI passes on it. A red CI never deploys, and
pull requests only run CI. The image is built on the runner and pushed to
`ghcr.io/salamon-projects/stepsfrom` with the workflow's own `GITHUB_TOKEN`.

One-time server preparation (Ubuntu 24.04, as the `deploy` user):

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker deploy
```

Repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `SSH_PRIVATE_KEY` | Private key whose public half is in `~deploy/.ssh/authorized_keys` |
| `SECRET_KEY_BASE` | `openssl rand -hex 64` |
| `POSTGRES_PASSWORD` | `openssl rand -hex 24` |
| `ADMIN_USER`, `ADMIN_PASSWORD` | Admin login |
| `LLM_API_KEY` | Optional: key for the language model that reads searches (Tensorix) |

Then, from Actions → Deploy → Run workflow:

1. `setup`: first deploy (installs kamal-proxy, starts PostGIS and the app).
2. `seed`: adds the launch destinations (unpublished).
3. `osm-import` with a destination slug, e.g. `makarska-riviera`.
4. `deploy`: deploys `main` again without a new commit.
5. `db-upgrade`: restarts the database container on the image in `config/deploy.yml`,
   keeping its data. Needed once whenever that image changes, before the new app
   version can boot (its migrations may need the new image). The first deploy after
   such a change fails its health check and leaves the old version running; run
   `db-upgrade`, then `deploy`.

Kamal connects to the server by IP address (`188.245.4.128`); the repository
variable `KAMAL_SERVER` overrides it.

## Jobs

Production uses Solid Queue for imports, measuring searched places (queue `areas`),
classification after edits, price refreshes and the recurring tasks. Run `bin/jobs`, or set `SOLID_QUEUE_IN_PUMA=1` to run it
inside Puma.

## Configuration

| Variable | Purpose |
|---|---|
| `ADMIN_USER`, `ADMIN_PASSWORD` | Admin sign-in on `/admin/login` (or credentials `admin.user` / `admin.password`). Required in production |
| `OVERPASS_URLS` | Overpass API endpoints, comma-separated (default: overpass-api.de, private.coffee, kumi.systems) |
| `NOMINATIM_URL` | Nominatim instance for looking up searched places (default: nominatim.openstreetmap.org) |
| `MAP_TILE_URL` | Map tile template (default: OpenStreetMap's tile server) |
| `PRICE_PROVIDERS` | Price providers to use, e.g. `stay22` |
| `LLM_API_KEY` | Key for the language model that reads searches (optional; without it names are matched directly). A repository secret for deploys |
| `LLM_BASE_URL`, `LLM_MODEL` | OpenAI-compatible endpoint and model (default: `https://api.tensorix.ai/v1`, `deepseek/deepseek-chat-v3.1`) |
| `*_TRACKING_URL` | Affiliate tracking templates, see above |

The OpenStreetMap tile server is fine at low traffic, but read its
[usage policy](https://operations.osmfoundation.org/policies/tiles/) and switch to a
tile provider as traffic grows.

## Tests and checks

```bash
bundle exec rspec
bin/rubocop
bin/brakeman
```

The specs need PostGIS and pgRouting. OSM imports are tested against a fixture
(`spec/fixtures/files/overpass/sample_bay.json`), with no network access.

## Data and licences

- Map data © OpenStreetMap contributors, available under the
  [Open Database License](https://www.openstreetmap.org/copyright). The attribution
  appears in the site footer and on every map.
- Leaflet © Volodymyr Agafonkin, BSD-2-Clause (`vendor/assets/leaflet/LICENSE`).

## Later

- Price provider adapters, once a programme grants API access.
- Automatic matching of booking-site listings to properties (name + distance), or
  GIATA/Vervotech mapping at scale.
- Lakes and rivers mapped as multipolygon relations; OSM water-polygons import.
- Signals from review text ("across the road", "10 minutes to the beach").
