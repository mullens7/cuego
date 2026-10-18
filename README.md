# Cuego table service

Static, dependency-free frontend with Supabase Auth, PostgREST and a transactional order RPC. Vercel serves `index.html` for admin and customer routes. Database schema is in `supabase/` and applied to the Cuego Supabase project.

## Routes
- `/` — guest welcome and search for a venue currently accepting orders. Table QR links continue directly to the venue menu.
- `/forvenues` — venue-facing introduction with `/forvenues/how-it-works`, `/forvenues/pricing` and `/forvenues/contact`.
- `/admin` — email/password sign in, venue creation and venue list.
- `/admin/{venue}` — overview, orders, menu and tables.
- `/v/{venue}/order?table={table_uuid}` — customer ordering page.

The first release takes **pay at venue** orders. It does not process online payments, tax, tips, refunds, modifiers or ingredient/allergen data. Do not present it as a paid online checkout. The customer submission is intentionally disabled until the venue owner adds items and tables and enables ordering. The staff order screen polls every six seconds. Sales figures represent placed orders excluding cancellations, not settled payments.

The QR print action uses `api.qrserver.com` to render a QR image from the public table URL. For a production rollout, replace this with first-party QR generation and add anti-abuse controls (rate limiting/CAPTCHA) to the guest ordering endpoint.

## Multi-tenant ordering foundation

This repository remains one static application on the existing Vercel project and one Supabase project. Apply the numbered `supabase/` SQL migrations in order before deploying corresponding frontend changes. Migrations 003–010 were applied to the existing Cuego Supabase project on 1 October 2026. They preserve legacy `venues` and orders while representing each venue as a location within an organisation.

- `/manage` (or legacy `/admin`) signs staff in and creates an organisation with its first location. A signed-in owner can create menus, tables, modifiers and station assignments.
- `/order/{organisationSlug}/{locationSlug}/table/{tableLabel}` is the fallback table QR URL. A single-location organisation can omit the location slug on the entry screen.
- `/display/{venueSlug}` is the authenticated, station-filtered touch display. Customer status and staff display refresh every three seconds; Supabase Realtime is not yet connected.
- A verified `location_domains.hostname` resolves a custom host to that same location. DNS and a Vercel project domain assignment are also required; inserting a domain row alone does not configure TLS or the Vercel alias. Keep `verification_status='pending'` until both are validated.
- New locations default to demo mode. Demo orders are marked `order_kind='demo'` and `payment_status='demo_simulated'`; no payment method is requested or charged. There is no Stripe integration or live online payment checkout yet.

The original pay-at-venue flow under `/v/{slug}/order` remains for compatibility. Do not use it as a live paid checkout. The first Victory Inn tenant still requires an authenticated owner to create it and its actual venue menu to be entered; no fake owner account or published menu data was inserted.

The frontend has no package manager, lint script, test runner or build step. Validate its JavaScript with `node --check app.js customer.js display.js config.js` (one file per invocation); the Vercel deployment serves these modules and styles as static assets. Exercise customer and staff flows at 320px, 375px, 430px and tablet width when a test tenant is available.

## Reserved administrator and venue accounts

Migration 011 privately reserves the platform role for `freddie@mullens.com` and the first Victory Inn owner role for `freddiemullenuk@icloud.com`. These reservations create no password and do not bypass email confirmation. On verified signup, the venue reservation creates the organisation, Hamble location, Bar/Kitchen stations and Table 12. Other venue accounts cannot call the protected platform overview RPC. The trigger and reservation tables are outside the exposed API schema.

Use `/superadmin` for the platform account and `/manage` for the venue account. Choose a password via Create account and confirm the email. `/account/reset` requests recovery; `/account/password` handles a valid recovery session. Supabase Auth Site URL should be `https://www.cuego.co.uk` with that site's `/manage` and `/account/password` allowed as redirect URLs. No invite emails were sent by this deployment.

## Public guest entry

Migration 012 adds `find_ordering_venues(text)`, a limited public lookup of name and route slugs for locations currently accepting orders. The homepage searches after two characters and sends a guest to `/order/{organisationSlug}/{locationSlug}`. It never displays dormant or paused venues, and does not guess a venue from the generic Cuego host. A venue must be onboarded, populated and switched to accepting orders before it appears. Venue account creation remains in `/manage`, linked from the For venues page.

## Victory Inn demonstration (18 October 2026)

- `/order/thevictoryinn` identifies the table; `/order/thevictoryinn/table/12` opens the menu directly.
- `/display/thevictoryinn` is the authenticated Bar/Kitchen display.
- `/admin/thevictoryinn` manages products, prices, availability, modifiers, tables, branding and stations.
- The confirmed platform administrator has an explicit membership for this demo. The reserved iCloud account gains owner membership after verified signup; no password was fabricated and no confirmation was bypassed.
- The uploaded `VI-Square-B.webp` is preserved unchanged at `assets/venues/thevictoryinn/logo.webp`.
- Food names and prices were transcribed from the main menu image linked by https://thevictoryinn.co.uk/eat on 18 October 2026. Descriptions were shortened. Drinks names were informed by https://thevictoryinn.co.uk/drink; drinks prices, soft drinks and glass sizes are illustrative demo data, not a verified live drinks menu. The ordering UI labels prices as preview data. No allergen-free claims were inferred.
- Demo checkout uses trusted database prices, modifier validation, stock checks, idempotency and station routing. The legacy pay-at-venue RPC rejects demo locations.
- Customer status/display poll every three seconds; menu changes refresh every five seconds while the menu is visible and no dialog is open. This remains polling, not Supabase Realtime subscriptions.
- The two timestamped migrations in `supabase/migrations/` follow numbered files 001–012 in `supabase/`; apply in that order on a new database. Both were applied to the existing project. Existing tenant data was preserved.
- `qa/mobile.html` provides actual 320px, 375px and 430px iframe viewports against the shared app for responsive flow checks. It contains no authentication bypass or private data.
- The future ordering domain is not configured or marked verified. Later, add the Vercel/DNS domain and its verified mapping to this location; the same app and database will serve it.
