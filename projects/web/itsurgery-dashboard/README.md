# IT Surgery dashboard — `https://dashboard.itsurgery.me`

**The code is not here.** This directory exists because this is where you
look for it. The dashboard is an n8n workflow, not a website:

| What | Where |
|------|-------|
| The workflow (data fetches + page builder) | [`automation/n8n/workflows/dashboard.json`](../../../automation/n8n/workflows/dashboard.json) |
| The monitoring page it links to | [`automation/n8n/workflows/monitoring.json`](../../../automation/n8n/workflows/monitoring.json) |
| The watchdog that emails when monitoring changes | [`automation/n8n/workflows/watchdog.json`](../../../automation/n8n/workflows/watchdog.json) |
| Deployment (push to main → live n8n) | [`.github/workflows/deploy-n8n.yml`](../../../.github/workflows/deploy-n8n.yml) via `automation/n8n/deploy.py` |
| The `dashboard.itsurgery.me` vanity host (nginx in front of n8n) | [`automation/ansible/roles/n8n/`](../../../automation/ansible/roles/n8n/), variable `n8n_dashboard_domain` |
| Design notes, what runs where, why it is not on Netlify | [`automation/n8n/README.md`](../../../automation/n8n/README.md) |

## How it works, in one paragraph

Opening `https://dashboard.itsurgery.me` hits an n8n webhook (path `dashboard`,
n8n basic auth). The workflow fetches upcoming bookings and unpaid invoices
from EspoCRM and Xero, the Stripe balance and next payout, new leads,
customers, Google reviews, the last site deploy and whether the website, CRM
and remote-help service answer. A Code node builds the whole page as HTML on
the server and the webhook responds with it. The browser receives finished
HTML and never holds a credential. `/monitoring` on the same host is the
sibling workflow and answers one question: is anything broken.

## Why it is not under `projects/web/`

The dashboard reads EspoCRM, Xero and Stripe and will later issue refunds. n8n
already holds all of those credentials and its own login. Served as a static
site from Netlify it would be public, every endpoint behind it would need its
own authentication, and secrets would live in a second place. The full
reasoning is in `automation/n8n/README.md` under "Why the dashboard is served
by n8n, not Netlify". Read that before proposing to move it.

## Editing it

Edit `automation/n8n/workflows/dashboard.json` and push to main; the deploy
workflow syncs it to the live n8n by workflow name. The page's HTML lives as
a string inside the "Build the page" Code node, which is awkward. A known
improvement, not yet done, is to keep the HTML as a real file beside the
workflow and have `deploy.py` inject it.
