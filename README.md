# StepsFrom

Finding and comparing **true** beachfront holidays.

Booking sites label many stays "beachfront" that are across a road or a long walk
from the water. [StepsFrom](https://stepsfrom.com) lists only properties whose position we have
**measured** against OpenStreetMap data, listed automatically once the measurement
puts them on the waterfront. For each one it shows
the distance to the water, what lies in between, and links to the booking sites that
carry it, with the cheapest one first once prices are available.

Principles:

- **No scraping.** Property and map data come from OpenStreetMap (ODbL). Booking-site
  links and prices come only from official affiliate programmes and APIs.
- **The measurement decides.** A booking site's "beachfront" label is stored as a
  hint and used to flag conflicts. It is never used to list a property.

## Stack

Ruby 3.3, Rails 8.1, PostgreSQL 16 + PostGIS 3 (`activerecord-postgis-adapter`),
HAML, SCSS (`dartsass-rails`), Propshaft. Pages are rendered on the server, with no
Hotwire, Stimulus or importmap. The only JavaScript is `app/assets/javascripts/map.js`,
which draws the maps with Leaflet 1.9.4 (vendored in `vendor/assets/leaflet`, BSD-2).
Background jobs and cache run on Solid Queue and Solid Cache. Tests use RSpec.

## Setup

You need PostgreSQL with the PostGIS extension, e.g. `apt install postgresql-16-postgis-3`.

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

1. **Destination.** Six launch destinations are seeded: Makarska Riviera, Poreč,
   Hvar, Kassandra, Chania coast and Rhodes east coast. They start unpublished. Add
   or adjust destinations in the admin by bounding box.
2. **Import.** Fetch coastline, lakes, beaches, roads and accommodation from
   the Overpass API, then measure every property. Run it with "Import from OSM" in
   the admin, or with:
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
   lakes, beaches, roads) that OSM no longer returns inside the bounding box are
   removed, so measurements always use the current map (features within about
   100 m of the box's edge are kept, and a layer that comes back empty removes
   nothing). Properties are never deleted: one that OSM no longer returns is
   flagged, leaves the site and is listed under "Not in OSM" in the admin. Until an
   admin edits or hides a property, its name, position and details follow OSM.

   Every Monday the websites of listed properties are checked
   (`Websites::Checker`, or `bin/rails websites:check` by hand). A page that is
   empty, missing (404/410), on a parked or vanished domain, or failing twice in a
   row loses its "Official website" link; sites that refuse automated checks keep
   it. The admin lists them under "Broken website"; entering a new address there
   checks it afresh. Whether a property still operates is a different question,
   left for when booking-site APIs can confirm it is bookable.
3. **Check.** Properties measured in a listed category (beachfront, steps from the
   water, short walk) are on the site automatically; nobody approves them. In the
   admin, "On the site" lists them. Correct a position if needed (which measures the
   property again), or hide one that is closed, misplaced or not a real
   accommodation. Edited and hidden properties keep their name, position and details
   on later imports.
   "OTA claim conflicts" lists properties that a booking site calls beachfront but
   that we measured further away.
4. **Listings.** On each property, add its page on Booking.com, Expedia, Hotels.com,
   Vrbo, Agoda or Trip.com. Optionally enter the position the site shows. If it is
   more than 150 m from ours, the property is flagged.
5. **Publish** the destination.

To re-measure without re-importing:

```bash
bin/rails waterfront:classify[makarska-riviera]
```

## How properties are classified

`Waterfront::Measurer` (`app/services/waterfront/measurer.rb`) measures in PostGIS,
from the building outline when OSM has one, otherwise from the point:

- the geodesic distance to the nearest sea coastline or lake (rivers are left out: a riverbank is not a beach);
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
| `not_waterfront` | Further: never listed |
| `unknown` | No water imported for the destination yet |

The public "How we verify and rank" page shows the same thresholds. It is required
for ranking transparency, so keep it accurate when you change them.

### Verified attributes

Waterfront is the first of several **verified attributes**. Each result is a
row in `verifications` (single-table inheritance): `Verifications::Waterfront`
holds the category, the headline distance (`distance_m`), the measurement
details in `evidence`. Properties keep only location data, plus `hidden_at`
and `reviewed_at` for an admin's decisions. A property is listed once its
waterfront result is in a listed category, unless it is hidden or missing from OSM.

To add an attribute, for example a verified sea view:

1. Create `app/models/verifications/sea_view.rb` (`< Verification`) with its
   `CATEGORIES`, `LISTED_CATEGORIES` and `store_accessor :evidence` keys.
   `subject` distinguishes several results of one type, for example one per
   landmark for a landmark view.
2. Write the measuring service (like `Waterfront::Classification`) that saves it.
3. Add the badge texts under `config/locales/en.yml` and show the result in the
   admin "Verifications" block and on the public pages.

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
`www.stepsfrom.com`, www redirects to the bare domain) and a PostGIS container
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

Then, from Actions → Deploy → Run workflow:

1. `setup`: first deploy (installs kamal-proxy, starts PostGIS and the app).
2. `seed`: adds the launch destinations (unpublished).
3. `osm-import` with a destination slug, e.g. `makarska-riviera`.
4. `deploy`: deploys `main` again without a new commit.

Kamal connects to the server by IP address (`188.245.4.128`); the repository
variable `KAMAL_SERVER` overrides it.

## Jobs

Production uses Solid Queue for imports, classification after edits, price refreshes
and the recurring tasks. Run `bin/jobs`, or set `SOLID_QUEUE_IN_PUMA=1` to run it
inside Puma.

## Configuration

| Variable | Purpose |
|---|---|
| `ADMIN_USER`, `ADMIN_PASSWORD` | Admin sign-in on `/admin/login` (or credentials `admin.user` / `admin.password`). Required in production |
| `OVERPASS_URLS` | Overpass API endpoints, comma-separated (default: overpass-api.de, private.coffee, kumi.systems) |
| `MAP_TILE_URL` | Map tile template (default: OpenStreetMap's tile server) |
| `PRICE_PROVIDERS` | Price providers to use, e.g. `stay22` |
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

The specs need PostGIS. OSM imports are tested against a fixture
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
- Lakes mapped as multipolygon relations; OSM water-polygons import.
- Signals from review text ("across the road", "10 minutes to the beach").
