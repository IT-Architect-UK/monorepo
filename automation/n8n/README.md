# n8n workflows

**The files in `workflows/` are the source of truth, not the n8n UI.**

Every push to `main` that touches this directory syncs these definitions to
the instance and activates them. If you edit a workflow in the n8n editor and
don't bring the change back here, the next push overwrites it.

That is the trade for having workflows reviewable, versioned and deployable to
a client's instance instead of living only inside one server.

## How to change a workflow

1. Prototype in the n8n editor — it is far easier than editing JSON
2. When it works: select all on the canvas (**Ctrl+A**, **Ctrl+C**)
3. Paste over the matching file in `workflows/`, keeping the top-level `name`
4. Commit and push. CI deploys it.

The name in the file is what CI matches on. **Renaming a workflow creates a
second one** rather than renaming the original — rename it in n8n too, or
delete the orphan.

## What runs where

| Workflow | Called by | Purpose |
|----------|-----------|---------|
| `cal-booking.json` | Cal.com webhooks | Creates or updates the customer and meeting in EspoCRM, raises the £5 Xero invoice, and handles reschedules and cancellations |
| `cal-get-pay-link.json` | The `/booked/` page on itsurgery.me | Returns the Xero payment link for a booking, which the page polls for while the invoice is being raised |
| `error-alert.json` | n8n itself, when another workflow fails | Emails the failure to Darren. Never runs on its own |
| `dashboard.json` | Darren, in a browser | The business dashboard — money, upcoming bookings, unpaid invoices |
| `monitoring.json` | Darren, in a browser | Whether the machinery is healthy — services, server, certificates, backups, updates |
| `watchdog.json` | A 15-minute schedule | Emails when the monitoring verdict *changes*. Never runs on demand |

## When something fails

Both live workflows name `n8n error alert` as their error workflow, so any
failed automatic execution emails Darren with the workflow, the node that
broke, the error message and a link to the execution.

n8n links error workflows by **id**, which belongs to one instance and would
break the name-matching this repository depends on. So the files carry
`settings.errorWorkflowName` instead — a key of ours, not n8n's — and
`deploy.py` resolves it to that instance's id after every workflow exists, then
strips it before sending. Rename the error workflow and you must rename it in
both places.

Two things to know before trying to test it:

- n8n does **not** run error workflows for manual executions. Only a real
  automatic run — a webhook, a schedule — will fire one.
- The error workflow **must be published**, like any other. n8n's Error Trigger
  documentation says otherwise, but on 2.x an unpublished workflow does not run
  and the alert simply never arrives. `deploy.py` activates everything.

## Setting it up on a new instance

Two repository secrets:

| Secret | Value |
|--------|-------|
| `N8N_BASE_URL` | `https://n8n.itsurgery.me` |
| `N8N_API_KEY` | From n8n → Settings → n8n API |

Then push, or run the workflow manually from the Actions tab.

## Credentials

Credentials are **not** in these files, and must not be. The JSON references
them by id and name; the secrets themselves stay in n8n, encrypted with that
instance's `N8N_ENCRYPTION_KEY`.

The consequence is that a workflow deployed to a *different* instance will
reference credential ids that don't exist there. Deploying to a client
therefore means creating credentials with the same names on their instance and
fixing up the ids — the sync script matches workflows by name but does not yet
do the same for credentials. Worth building when there is a second instance to
build it against.

## Why the dashboard is served by n8n, not Netlify

The obvious home for a dashboard is the website — same repo, same deploy,
`dash.itsurgery.me` and a certificate for free. We chose n8n instead, and the
reason is worth remembering before anyone moves it.

The dashboard reads EspoCRM, Xero and Stripe, and will later issue refunds.
n8n already holds all of those credentials. Served from n8n, the page is built
on the server and arrives at the browser as finished HTML — the browser never
holds a key, there is no cross-origin call, and the login is n8n's own basic
auth rather than something we would have to build and maintain.

Served from Netlify, the page would be public, every n8n endpoint behind it
would need its own authentication, and anything the page knows a visitor also
knows. That is all solvable, but it is a login system, CORS configuration and a
second place for secrets to live — in exchange for a nicer address.

TLS is not a factor either way: n8n has a Let's Encrypt certificate already.

If a prettier address matters later, put `dash.itsurgery.me` in front of the
n8n webhook with nginx. That keeps the security model and changes only the URL.

## Where the monitoring page gets its facts

`https://dashboard.itsurgery.me/monitoring` answers one question: is anything
broken. It has three sources and no memory — every load is a fresh look.

1. **The services**, checked by asking them. Anything that answers at all
   counts as up, including a `401` from Stripe or Xero: an API that refuses an
   unauthenticated request is working exactly as it should.
2. **The server**, from `/vitals.json` — a snapshot the `vitals` Ansible role
   writes every five minutes on the VPS itself. nginx serves that file only to
   localhost and the Docker bridge, so n8n can read it and nobody else can.
   The page shows how old the snapshot is and turns amber past 15 minutes and
   red past an hour, because stale numbers that look fine are worse than none.
3. **The last deploy**, from the GitHub Actions API.

The thresholds are on the page itself rather than buried here: disks amber at
80% and red at 90%, certificates amber at 21 days and red at 7, backups amber
after 36 hours and red after 72.

Every check node is set to `continueRegularOutput`, so a refused connection or
a DNS failure becomes an item rather than an exception. Without that, one
unreachable service would abort the run and the page would not render at all —
monitoring that goes dark exactly when something is wrong. A check that fails
that way is **red**, labelled "no answer": not being able to reach something is
a down signal, not a mystery.

Grey is reserved for a check that did not run at all. It is **not** treated as
healthy — it turns the banner amber and is named in a panel above the diagram,
because a blind spot is the one fault you cannot spot by reading the rest of
the page. Grey should be rare; if it appears, the workflow has been edited or a
node has been removed.

## The watchdog, and why it has no rules of its own

`monitoring.json` answers `?format=json` with the same verdict it just
rendered as a page — same run, same rules. `watchdog.json` fetches that every
fifteen minutes and compares it with the last one it saw. The health rules
therefore exist in exactly one place, and the email can never disagree with
what the page shows.

It asks over the public URL rather than reaching into n8n directly, so nginx,
the certificate and basic auth are all on the path being tested. If the
monitoring page cannot be reached at all, that is the one email the watchdog
sends on its own account — no other thing here can report that failure.

**Only transitions are reported.** Something that emails every fifteen minutes
while a disk is full is something you filter into a folder and stop reading,
and then it is worth nothing on the day it matters. Recoveries are reported
too, so a problem that fixes itself closes rather than leaving you wondering.

Previous state lives in `$getWorkflowStaticData('global')`, which survives
between executions but **not** a redeploy of the workflow. That is deliberate:
after a deploy the first run re-learns the world silently instead of emailing
about things that were already true.

Two traps worth not rediscovering:

- **A Code node runs once for all items by default, and the bare `$json`
  shorthand is undefined in that mode.** Use `$input.first().json`. Getting
  this wrong fails at run time, in the background, and looks exactly like
  nothing being wrong.
- **Something newly appeared and already unhealthy is a problem, not a
  recovery.** An early version put it in the recovered list and produced the
  subject line "Recovered" for a container that had just died.

## Why a green deploy can be trusted

The last step of every deploy reads each workflow back from n8n and compares it
with the file that was just sent — node by node, plus connections and the
settings we set. Any difference fails the build and names the field.

This exists because it was needed. On 14 August a node was added to the cancel
branch, the deploy went green, and the node never appeared on the instance. Five
further deploys stayed green. It surfaced on 19 August only because a real
cancelled booking failed to raise its alert — the API had been accepting every
request and reporting success, which is not the same as applying it.

The check asserts only what we set. Ids, timestamps, `versionId` and n8n's own
default settings are ignored: comparing those would fail on every run and the
check would be switched off within a week.

## Running it by hand

```bash
export N8N_BASE_URL=https://n8n.itsurgery.me
export N8N_API_KEY=...
python3 deploy.py --dry-run   # show what would change
python3 deploy.py             # apply it
```

No dependencies beyond Python 3 — it uses the standard library only, so it runs
on a bare CI runner or a client's server without a package install.
