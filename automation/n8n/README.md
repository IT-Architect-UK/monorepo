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
| `cal-get-pay-link.json` | The `/booked/` page on itsurgery.me | Returns the Xero payment link for a booking, which the page polls for while the invoice is being raised |

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

## Running it by hand

```bash
export N8N_BASE_URL=https://n8n.itsurgery.me
export N8N_API_KEY=...
python3 deploy.py --dry-run   # show what would change
python3 deploy.py             # apply it
```

No dependencies beyond Python 3 — it uses the standard library only, so it runs
on a bare CI runner or a client's server without a package install.
