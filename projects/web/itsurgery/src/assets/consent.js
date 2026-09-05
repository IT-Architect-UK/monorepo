/* Cookie consent and the Google tag (Analytics, and Ads once an ID is set).
 *
 * Nothing is sent to Google until the visitor accepts. That is the plain
 * reading of UK PECR for analytics and advertising cookies, and it is simpler
 * than Google's "advanced" consent mode, which still pings Google before
 * consent. So: banner first; on Accept, load gtag.js and grant every consent
 * type; on Decline, load nothing and remember the choice for a year. The
 * choice can be changed later from the "Cookie settings" link in the footer.
 *
 * Events sent when tracking is on (all custom, no personal data):
 *   book_click        - any Book button or link to /book/
 *   contact_whatsapp  - any wa.me link
 *   generate_lead     - a form landed on /thanks/ (form=quote|site-issue)
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

  var loaded = false;
  function loadTag() {
    if (loaded) return; loaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };
    gtag('consent', 'default', {
      ad_storage: 'granted', ad_user_data: 'granted', ad_personalization: 'granted', analytics_storage: 'granted'
    });
    gtag('js', new Date());
    if (GA)  gtag('config', GA, { anonymize_ip: true });
    if (ADS) gtag('config', ADS, { allow_enhanced_conversions: false });
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA || ADS);
    document.head.appendChild(s);
    wireEvents();
  }

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

  function show() { cfg.hidden = false; }
  function hide() { cfg.hidden = true; }

  cfg.querySelector('[data-consent="accept"]').addEventListener('click', function () { write('granted'); hide(); loadTag(); });
  cfg.querySelector('[data-consent="decline"]').addEventListener('click', function () { write('denied'); hide(); });

  // Footer link reopens the banner so a choice can be changed.
  var reopen = document.querySelectorAll('[data-consent="settings"]');
  for (var i = 0; i < reopen.length; i++) {
    reopen[i].hidden = false;
    reopen[i].addEventListener('click', function (e) { e.preventDefault(); show(); });
  }

  var state = read();
  if (state === 'granted') loadTag();
  else if (state === null) show();
})();
