# Cuego development rules

Cuego is primarily used on phones. Build every customer and venue workflow for a narrow touchscreen first, then enhance the layout for tablets and desktops.

- A customer must be able to scan a table QR code, read the menu, add items, inspect the basket, choose a table if needed, and place an order comfortably with one hand.
- Venue owners and staff must be able to add items, change stock/availability, read incoming orders, and mark an order ready or delivered on a phone. A dedicated touchscreen layout must also remain usable.
- Check common viewport widths from 320px to 430px, tablet widths, and desktop. Avoid horizontal page scrolling, clipped text, overlapping controls, or actions hidden behind fixed bars, keyboards, or browser safe areas.
- Use legible type (16px for form inputs), visible labels, strong contrast, and touch targets of at least 44px for frequent actions. Support text enlargement and both portrait and landscape orientation.
- Keep the primary mobile action within easy reach. Use compact layouts and a persistent basket entry point when customers browse a long menu. Keep the full checkout readable and operable with the on-screen keyboard visible.
- Test the actual flow on a narrow mobile viewport after UI changes. Do not mark a page complete based only on its desktop layout or a successful build.
- Keep checkout prices and stock validated by the database. Do not move these checks into browser-only code to simplify a mobile UI.
