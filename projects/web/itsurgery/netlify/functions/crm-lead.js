'use strict';

/**
 * crm-lead — turn a Netlify form submission into an EspoCRM Lead.
 *
 * Netlify captures the submission and emails Darren first; this runs afterwards
 * from an outgoing webhook. That ordering is the whole point of the design: if
 * the CRM is down, mid-upgrade, or the VPS is rebooting, the enquiry is still
 * safely in Netlify and still reached the inbox. Posting the form straight at
 * the CRM would make a first customer's enquiry depend on a single small server
 * being up at that moment.
 *
 * Required environment variables (set in Netlify, never in Git):
 *   ESPOCRM_LEAD_CAPTURE_URL   full endpoint including the capture key, e.g.
 *                              https://crm.itsurgery.me/api/v1/LeadCapture/<key>
 *   NETLIFY_WEBHOOK_JWS_SECRET the JWS secret configured on the webhook
 *
 * The capture key is not a login. Worst case if it leaks is junk Leads, not
 * read access to customer data — which is why this uses Lead Capture rather
 * than an API user.
 */

const crypto = require('crypto');

const b64url = (buf) => buf.toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

/**
 * Netlify signs outgoing webhooks with a JWS in x-webhook-signature. The token
 * carries a sha256 of the body, so verifying it proves both origin and that the
 * payload was not altered. Without this the function is an open endpoint that
 * anyone could use to inject Leads.
 */
function verifySignature(token, rawBody, secret) {
  if (!token) return { ok: false, why: 'no signature header' };

  const parts = token.split('.');
  if (parts.length !== 3) return { ok: false, why: 'malformed JWS' };

  const [header, payload, signature] = parts;

  const expected = b64url(
    crypto.createHmac('sha256', secret).update(`${header}.${payload}`).digest()
  );

  // Constant-time compare. A plain === leaks timing information about how much
  // of the signature matched.
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { ok: false, why: 'signature mismatch' };
  }

  let claims;
  try {
    claims = JSON.parse(Buffer.from(payload, 'base64').toString('utf8'));
  } catch {
    return { ok: false, why: 'unparseable claims' };
  }

  const bodyHash = crypto.createHash('sha256').update(rawBody).digest('hex');
  if (claims.sha256 && claims.sha256 !== bodyHash) {
    return { ok: false, why: 'body hash mismatch' };
  }

  return { ok: true };
}

/**
 * "Darren Pilkington" -> { firstName: 'Darren', lastName: 'Pilkington' }
 * "Mary Jane Smith"   -> { firstName: 'Mary Jane', lastName: 'Smith' }
 * "Darren"            -> { firstName: null, lastName: 'Darren' }
 *
 * Splitting on the LAST space, not the first, so multi-word given names survive.
 * A single word becomes the surname because that is the field EspoCRM treats as
 * the record's name.
 */
function splitName(full) {
  const name = (full || '').trim().replace(/\s+/g, ' ');
  if (!name) return { firstName: null, lastName: 'Website enquiry' };

  const i = name.lastIndexOf(' ');
  if (i === -1) return { firstName: null, lastName: name };

  return { firstName: name.slice(0, i), lastName: name.slice(i + 1) };
}

const TYPE_LABELS = {
  personal: 'Home / personal IT',
  business: 'Business IT',
};

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method not allowed' };
  }

  const endpoint = process.env.ESPOCRM_LEAD_CAPTURE_URL;
  const secret = process.env.NETLIFY_WEBHOOK_JWS_SECRET;

  if (!endpoint || !secret) {
    console.error('crm-lead: missing ESPOCRM_LEAD_CAPTURE_URL or NETLIFY_WEBHOOK_JWS_SECRET');
    return { statusCode: 500, body: 'Not configured' };
  }

  const rawBody = event.body || '';
  const sig = event.headers['x-webhook-signature'] || event.headers['X-Webhook-Signature'];

  const check = verifySignature(sig, rawBody, secret);
  if (!check.ok) {
    console.warn(`crm-lead: rejected unsigned or invalid request (${check.why})`);
    return { statusCode: 401, body: 'Invalid signature' };
  }

  let body;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return { statusCode: 400, body: 'Invalid JSON' };
  }

  // Netlify has used both shapes over time depending on the event type.
  const submission = body.payload || body;
  const data = submission.data || {};
  const submissionId = submission.id || 'unknown';

  const { firstName, lastName } = splitName(data.name);

  const notes = [];
  if (data.type) notes.push(`Enquiry type: ${TYPE_LABELS[data.type] || data.type}`);
  if (data.when) notes.push(`Best time to call: ${data.when}`);
  if (data.problem) notes.push('', data.problem);

  // EspoCRM's docs are explicit: send null for empty values, not "".
  const lead = {
    firstName: firstName || null,
    lastName: lastName || null,
    emailAddress: (data.email || '').trim() || null,
    phoneNumber: (data.phone || '').trim() || null,
    description: notes.length ? notes.join('\n') : null,
    // Lead Source is deliberately NOT sent. The Lead Capture record sets it to
    // "Web Site" itself, and any field absent from that record's Payload Fields
    // list is discarded anyway — so sending it is at best redundant.
  };

  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify(lead),
      signal: AbortSignal.timeout(10000),
    });

    if (!res.ok) {
      const detail = (await res.text()).slice(0, 300);
      // Deliberately not logging the lead itself — function logs are not the
      // place for a customer's name, phone number and problem description.
      console.error(`crm-lead: EspoCRM returned ${res.status} for submission ${submissionId}: ${detail}`);
      return { statusCode: 502, body: 'CRM rejected the lead' };
    }

    console.log(`crm-lead: created lead from submission ${submissionId}`);
    return { statusCode: 200, body: 'OK' };
  } catch (err) {
    console.error(`crm-lead: could not reach EspoCRM for submission ${submissionId}: ${err.message}`);
    // The submission is still in Netlify and the email already went out, so
    // nothing is lost — it just needs entering by hand.
    return { statusCode: 502, body: 'CRM unreachable' };
  }
};
