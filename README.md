# Cuego table service

Static, dependency-free frontend with Supabase Auth, PostgREST and a transactional order RPC. Vercel serves `index.html` for admin and customer routes. Database schema is in `supabase/` and applied to the Cuego Supabase project.

## Routes
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
