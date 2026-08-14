# MeshCentral — remote support server

Runs MeshCentral at `https://help.itsurgery.me`: the server a customer's
computer connects back to so we can see their screen and, with their
permission, take control of it.

## Why this rather than a commercial tool

The people we support are exactly the people scammers target, and the scam
script is *"install this remote access program and read me the code"*. Microsoft
have published research on criminals doing precisely that through Quick Assist.
So the tool matters less than where it comes from.

With MeshCentral the assistant is downloaded **from our own domain**, during a
video call the customer booked themselves, and the permission prompt on their
screen carries our name. Nothing about that resembles a cold call. It is also
free and self-hosted, which means no per-technician fee eating into an hourly
job, and no third party holding a remote-control channel into customer machines.

## Running it

```bash
ansible-playbook playbooks/deploy-meshcentral.yml
```

No vault password: this role holds no secrets. The admin account is created
through the web interface and its password belongs in Bitwarden.

**DNS must resolve before the first run.** Certbot proves ownership over plain
HTTP, so `help.itsurgery.me` needs its A record pointing at the VPS or the
certificate step fails.

## First run — close registration afterwards

MeshCentral has no admin account until somebody registers one, and its
account-creation command line is documented as an offline recovery tool rather
than a setup step. So:

1. Run the playbook. It prints a warning that registration is open.
2. Go to `https://help.itsurgery.me/` and create your account **immediately**.
   The first account becomes the site administrator.
3. Set `meshcentral_allow_new_accounts: false` in
   `inventory/group_vars/meshcentral/vars.yml`.
4. Run the playbook again.

Between steps 1 and 3, anyone who finds the URL can create an account. Do it in
one sitting.

## How a support session works

1. The customer books, pays, and joins the Cal Video call at the agreed time.
2. They are talking to a named person before anything is downloaded — that
   ordering is the point, not an accident.
3. We send them to `help.itsurgery.me` to download the assistant.
4. They run it. A prompt on their machine asks whether to allow the session,
   showing who is asking.
5. Access ends when the session ends.

## What is where

| Path | What it holds |
|------|---------------|
| `/opt/meshcentral/meshcentral-data` | Database, server certificates, `config.json` |
| `/opt/meshcentral/meshcentral-files` | Files uploaded through the console |
| `/opt/meshcentral/meshcentral-web` | Branding overrides, if any |
| `/opt/meshcentral/backups` | Nightly archives, collected by Restic |

`config.json` is written by Ansible. Editing it on the server works until the
next run overwrites it — change the template instead.

## Backups

Nightly at 03:15, after the n8n backup so the two never fight over the disk.
The container is stopped for the few seconds the archive takes, because the
local database is a set of files being written live and half a record restores
no better than none.

**The archive contains the server's own key material.** That is deliberate —
restore without it and every agent already installed on a customer machine can
no longer verify the server, which means visiting each of them again. It also
means these archives are worth stealing. Treat them accordingly.

Restore: stop the container, unpack the archive over `/opt/meshcentral`, start
it again.

## Things worth knowing

- **The hostname is baked into every agent.** Renaming the server orphans every
  installed agent. Treat it as a migration.
- **WebRTC is off.** Behind a reverse proxy the direct path is the awkward one;
  relaying through the server is predictable, which matters more than raw
  throughput when someone is watching you work on their machine.
- **The proxy timeout is 330s**, longer than MeshCentral's 300s agent keepalive.
  Shorter and nginx cuts connections the application still thinks are healthy.
- **No swap on this host before now.** The playbook adds 2G first — with none,
  memory pressure kills a process outright, and it might not be this one.

## Not yet verified

Do not put these on the website until they have been:

- How far branding goes on the free build.
- macOS coverage. The assistant is Windows-focused; Macs use the standard agent
  and that path has not been tested.
