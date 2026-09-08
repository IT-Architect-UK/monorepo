/* Cookie consent and the Google tag (Analytics and Ads), in Google's
 * "advanced" consent mode.
 *
 * The tag loads on every page but starts with every consent type DENIED. In
 * that state it sets no cookies and stores nothing on the device; it sends
 * only cookieless, anonymous pings, which is what Google requires for Ads
 * measurement in the UK and EU and what lets Ads model conversions from
 * people who decline. When the visitor accepts, consent is updated to
 * GRANTED and full measurement (cookies included) starts. Decline leaves it
 * denied. The choice is kept for a year and can be changed from the
 * "Cookie settings" link in the footer.
 *
 * This replaced the earlier "basic" mode (no tag at all until consent) on
 * 2026-09-08: Google's tag checker never consents, so Ads reported the tag
 * as missing and got nothing from anyone who declined.
 *
 * Events sent (all custom, no personal data):
 *   book_click        - any Book button or link to /book/
 *   contact_whatsapp  - any wa.me link
 *   generate_lead     - a form landed on /thanks/ (form=quote|site-issue|question)
 *   booking_confirmed - a booking landed on /booked/
 */
(function () {
  var cfg = document.getElementById('consent-banner');
  if (!cfg) return;
  var GA = cfg.getAttribute('data-ga') || '';
  var ADS = cfg.getAttribute('data-ads') || '';
  if (!GA && !ADS) return;

  var KEY = 'consent';           // "granted" | "denied", with a timestamp
  var YEAR = 365 * 24 * 60 * 60 * 1000;

  function read() {
    try {
      var v = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (v && v.at && Date.now() - v.at < YEAR) return v.state;
    } catch (e) {}
    return null;
  }
  function write(state) {
    try { localStorage.setItem(KEY, JSON.stringify({ state: state, at: Date.now() })); } catch (e) {}
  }

  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };

  var ALL = ['ad_storage', 'ad_user_data', 'ad_personalization', 'analytics_storage'];
  function consentState(v) { var o = {}; for (var i = 0; i < ALL.length; i++) o[ALL[i]] = v; return o; }

  /* Default: everything denied, before the tag loads. url_passthrough keeps
     the ad click id in the URL between pages so a later conversion can still
     be attributed without a cookie; ads_data_redaction strips ad click ids
     from the pings while ad_storage is denied. */
  var defaults = consentState('denied');
  defaults.wait_for_update = 500;
  gtag('consent', 'default', defaults);
  gtag('set', 'url_passthrough', true);
  gtag('set', 'ads_data_redaction', true);

  gtag('js', new Date());
  if (GA)  gtag('config', GA, { anonymize_ip: true });
  if (ADS) gtag('config', ADS, { allow_enhanced_conversions: false });
  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA || ADS);
  document.head.appendChild(s);

  function grant() { gtag('consent', 'update', consentState('granted')); }

  function wireEvents() {
    document.addEventListener('click', function (e) {
      var a = e.target.closest && e.target.closest('a');
      if (!a) return;
      var href = a.getAttribute('href') || '';
      if (href.indexOf('wa.me') !== -1) gtag('event', 'contact_whatsapp', { link_text: (a.textContent || '').trim().slice(0, 40) });
      else if (href.indexOf('/book/') === 0) gtag('event', 'book_click', { service: (href.split('service=')[1] || 'default').split('&')[0] });
    });
    var path = location.pathname;
    if (path === '/thanks/') {
      var form = new URLSearchParams(location.search).get('form') || 'unknown';
      gtag('event', 'generate_lead', { form: form });
    } else if (path === '/booked/') {
      gtag('event', 'booking_confirmed', {});
    }
  }
  wireEvents();

  function show() { cfg.hidden = false; }
  function hide() { cfg.hidden = true; }

  cfg.querySelector('[data-consent="accept"]').addEventListener('click', function () { write('granted'); hide(); grant(); });
  cfg.querySelector('[data-consent="decline"]').addEventListener('click', function () { write('denied'); hide(); });

  // Footer link reopens the banner so a choice can be changed.
  var reopen = document.querySelectorAll('[data-consent="settings"]');
  for (var i = 0; i < reopen.length; i++) {
    reopen[i].hidden = false;
    reopen[i].addEventListener('click', function (e) { e.preventDefault(); show(); });
  }

  var state = read();
  if (state === 'granted') grant();
  else if (state === null) show();
})();
