# Cuego table service

Static, dependency-free frontend with Supabase Auth, PostgREST and a transactional order RPC. Vercel serves `index.html` for admin and customer routes. Database schema is in `supabase/` and applied to the Cuego Supabase project.

## Routes
- `/admin` — email/password sign in, venue creation and venue list.
- `/admin/{venue}` — overview, orders, menu and tables.
- `/v/{venue}/order?table={table_uuid}` — customer ordering page.

The first release takes **pay at venue** orders. It does not process online payments, tax, tips, refunds, modifiers or ingredient/allergen data. Do not present it as a paid online checkout. The customer submission is intentionally disabled until the venue owner adds items and tables and enables ordering. The staff order screen polls every six seconds. Sales figures represent placed orders excluding cancellations, not settled payments.

The QR print action uses `api.qrserver.com` to render a QR image from the public table URL. For a production rollout, replace this with first-party QR generation and add anti-abuse controls (rate limiting/CAPTCHA) to the guest ordering endpoint.
