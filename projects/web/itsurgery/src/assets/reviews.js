/* Google reviews, live from the n8n endpoint (automation/n8n/workflows/reviews.json).
   Fills [data-reviews-summary] and [data-reviews-list] on /reviews/, and the
   small [data-reviews-strip] on the home page. Every element starts hidden
   and the fallback text starts visible, so a failed or blocked fetch leaves
   an honest page rather than an empty one. Only text is inserted - never
   HTML from the response. */
(function () {
  var me = document.currentScript;
  var endpoint = me && me.getAttribute('data-endpoint');
  if (!endpoint || !window.fetch) return;

  function stars(n) {
    var full = Math.round(n || 0), s = '';
    for (var i = 0; i < 5; i++) s += i < full ? '★' : '☆';
    return s;
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e;
  }

  fetch(endpoint, { credentials: 'omit' })
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (d) {
      if (!d || !d.ok || !d.count) return;

      var summary = document.querySelector('[data-reviews-summary]');
      if (summary) {
        summary.querySelector('.reviews-stars').textContent = stars(d.rating);
        summary.querySelector('.reviews-score').textContent = d.rating.toFixed(1) + ' out of 5 from ' + d.count + ' Google review' + (d.count === 1 ? '' : 's');
        if (d.mapsUrl) summary.querySelector('.reviews-google').href = d.mapsUrl;
        summary.hidden = false;
      }

      var list = document.querySelector('[data-reviews-list]');
      if (list && d.reviews.length) {
        d.reviews.forEach(function (r) {
          var li = el('li', 'review');
          li.appendChild(el('p', 'review-stars', stars(r.rating))).setAttribute('aria-label', r.rating + ' out of 5');
          li.appendChild(el('blockquote', 'review-text', r.text));
          li.appendChild(el('p', 'review-meta', r.author + (r.when ? ' · ' + r.when : '')));
          list.appendChild(li);
        });
        list.hidden = false;
        var fb = document.querySelector('[data-reviews-fallback]'); if (fb) fb.hidden = true;
      }

      var strip = document.querySelector('[data-reviews-strip]');
      if (strip) {
        strip.querySelector('.reviews-stars').textContent = stars(d.rating);
        strip.querySelector('.reviews-score').textContent = d.rating.toFixed(1) + '/5 on Google from ' + d.count + ' review' + (d.count === 1 ? '' : 's');
        var q = d.reviews.filter(function (r) { return r.rating >= 4 && r.text.length < 220; })[0];
        if (q) strip.querySelector('.reviews-quote').textContent = '“' + q.text + '” — ' + q.author;
        strip.hidden = false;
      }
    })
    .catch(function () { /* fallback stays */ });
})();
