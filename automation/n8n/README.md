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
