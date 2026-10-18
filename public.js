// Public Cuego pages. The directory only exposes locations that are accepting orders.
let searchVersion = 0;

export function guestPage(render, request, escapeHtml) {
  searchVersion++;
  render(`<main class="guest-home"><div class="guest-orbit" aria-hidden="true"></div><div class="guest-content shell">
    <p class="guest-kicker"><span class="guest-dot"></span> TABLE SERVICE, MADE SIMPLE</p>
    <h1>Good times start<br><em>at your table.</em></h1>
    <p class="guest-intro">Find where you are, explore the menu, and order right from your phone.</p>
    <div class="venue-finder"><label for="venue-search">Where are you today?</label>
      <div class="venue-input-wrap"><span aria-hidden="true">⌕</span><input id="venue-search" type="search" autocomplete="off" enterkeyhint="search" maxlength="80" placeholder="Search for your venue" aria-describedby="venue-help venue-results" /></div>
      <p id="venue-help" class="guest-help">Or scan the QR code on your table to go straight to the menu.</p>
      <div id="venue-results" class="venue-results" role="status" aria-live="polite"></div>
    </div></div><div class="guest-bottom shell"><span>Find your table. Order what you love.</span><span>↓</span></div></main>`);
  const input = document.getElementById('venue-search');
  const results = document.getElementById('venue-results');
  let timer;
  input.addEventListener('input', () => {
    clearTimeout(timer);
    const query = input.value.trim();
    const version = ++searchVersion;
    if (query.length < 2) { results.innerHTML = ''; return; }
    results.innerHTML = '<p class="venue-message">Searching venues…</p>';
    timer = setTimeout(async () => {
      try {
        const venues = await request('/rest/v1/rpc/find_ordering_venues', {method:'POST', body:{p_query:query}, auth:false});
        if (version !== searchVersion || !results.isConnected) return;
        results.innerHTML = Array.isArray(venues) && venues.length
          ? `<ul class="venue-list">${venues.map(v => `<li><a href="/order/${encodeURIComponent(v.organisation_slug)}/${encodeURIComponent(v.location_slug)}" data-link><span class="venue-mark" aria-hidden="true">${escapeHtml(v.name?.slice(0,1)||'V')}</span><span class="venue-name">${escapeHtml(v.name)}</span><span class="venue-arrow" aria-hidden="true">→</span></a></li>`).join('')}</ul>`
          : '<p class="venue-message">No ordering venue found. Check the name or ask the team for their QR code.</p>';
      } catch {
        if (version === searchVersion && results.isConnected) results.innerHTML = '<p class="venue-message">We can’t search venues right now. Please try again, or scan the QR code at your table.</p>';
      }
    }, 200);
  });
}

const venueNav = '<div class="venues-subnav"><a href="/forvenues" data-link>Overview</a><a href="/forvenues/how-it-works" data-link>How it works</a><a href="/forvenues/pricing" data-link>Pricing</a><a href="/forvenues/contact" data-link>Contact</a></div>';

export function forVenuesPage(render, page) {
  const content = {
    '': `<p class="venues-eyebrow">CUEGO FOR VENUES</p><h1>More service.<br><em>Less waiting.</em></h1><p class="venues-lead">Give your guests a simple way to order from their table, and give your team a clearer view of what needs doing.</p><div class="venues-actions"><a class="btn" href="/forvenues/how-it-works" data-link>See how it works <span aria-hidden="true">→</span></a><a class="venues-text-link" href="/manage" data-link>Venue sign in <span aria-hidden="true">↗</span></a></div><div class="venues-steps"><div><span>01</span><h2>One scan</h2><p>Guests open your menu from a table QR code, with their table already selected.</p></div><div><span>02</span><h2>One smooth order</h2><p>They choose what they want on their phone, with clear prices and options.</p></div><div><span>03</span><h2>One live view</h2><p>Your team sees incoming orders and moves them through service.</p></div></div>`,
    'how-it-works': `<p class="venues-eyebrow">HOW IT WORKS</p><h1>From table to team.</h1><p class="venues-lead">Cuego connects your menu, tables and service screen in one place.</p><div class="venues-steps"><div><span>01</span><h2>Set up your venue</h2><p>Add tables, menu categories, products and availability in your management area.</p></div><div><span>02</span><h2>Let guests order</h2><p>A table QR opens your branded menu. Guests can also find your venue on Cuego and enter their table.</p></div><div><span>03</span><h2>Keep service moving</h2><p>Orders reach the staff display, where the team can prepare and complete them.</p></div></div><p class="venues-note">A demonstration mode is available while online payments are being connected. It is clearly marked and never charges a guest.</p>`,
    'pricing': `<p class="venues-eyebrow">PRICING</p><h1>Talk to us about your venue.</h1><p class="venues-lead">We’re working with our first venues and finalising commercial plans. We’ll explain the setup and pricing before you commit.</p><div class="venues-simple"><h2>Built around your service</h2><p>One organisation can manage multiple locations, menus, tables and staff displays in the same Cuego platform.</p><a class="btn" href="/forvenues/contact" data-link>Get in touch <span aria-hidden="true">→</span></a></div>`,
    'contact': `<p class="venues-eyebrow">CONTACT</p><h1>Let’s talk tables.</h1><p class="venues-lead">Interested in Cuego for your venue? Tell us what you run and how your team works. We’d love to hear from you.</p><div class="venues-simple"><h2>Venue enquiries</h2><p>Get in touch directly with the Cuego team.</p><a class="btn" href="mailto:freddie@mullens.com?subject=Cuego%20venue%20enquiry">Email Cuego <span aria-hidden="true">↗</span></a></div>`
  };
  render(`<main class="venues-page"><div class="shell venues-shell">${venueNav}<div class="venues-content">${content[page] || '<h1>Page not found</h1><p>That page is not available.</p><a href="/forvenues" data-link>Back to For venues</a>'}</div></div></main>`);
}
