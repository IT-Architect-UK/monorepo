# vitals role

n8n runs in a container and cannot see the machine underneath it: not the
disk, not the certificates, not whether a reboot is pending. This role puts a
small script on the host that writes those facts to a JSON file on a timer.
The n8n role's dashboard site serves that file to the container, and nobody
else, as `/vitals.json`, and the dashboard's monitoring page reads it.

A read-only snapshot on a timer, deliberately. Giving a container a socket or
a shell on its host so a page can run commands is a far larger hole than any
dashboard is worth.

Applied by `playbooks/deploy-vitals.yml` to the `n8n` group.

## What it installs

| Path | What |
|------|------|
| `/usr/local/bin/vps-vitals.sh` | The script, from `templates/vitals.sh.j2`. Written without `jq` on purpose: one less package on a box where this script is the thing that says when something is missing |
| `/etc/systemd/system/vps-vitals.service` | Oneshot unit that runs it |
| `/etc/systemd/system/vps-vitals.timer` | `OnCalendar=<vitals_schedule>`, `OnBootSec=60`, `Persistent=true` |
| `/opt/vitals/vitals.json` | The snapshot, mode 0644. Written to a temp file and moved into place, so a reader never sees a half-written one |
| `/opt/vitals/cache/` | The slow half's cache, below |

The role writes the first snapshot immediately, so the page is not blank
until the timer first fires, and checks the file parses as JSON, so a
malformed script fails the playbook rather than silently blanking the page.

## Fast half, slow half

Memory, load, disks, containers and systemd units are cheap and are collected
every run. Certificates, backup ages and pending updates are expensive
(`apt-get -s upgrade` alone parses the whole package database) and change on
the scale of hours, so they are cached under `vitals_dir/cache` and
recomputed only when the cache is older than `vitals_slow_max_age`.
`slowAgeSeconds` in the output says how stale that half is.

## Variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `vitals_dir` | `/opt/vitals` | Directory nginx serves from (world-readable; nothing in it is secret) |
| `vitals_file` | `/opt/vitals/vitals.json` | The snapshot |
| `vitals_schedule` | `*:0/1` (every minute) | systemd `OnCalendar` |
| `vitals_slow_max_age` | `900` seconds | Recompute the slow half when older than this |
| `vitals_disk_paths` | `/` | Filesystems to report |
| `vitals_backup_dirs` | `/opt/n8n/backups`, `/opt/espocrm/backups`, `/opt/meshcentral/backups` | Report the age of the newest file in each. A backup that quietly stopped looks exactly like one that is working |
| `vitals_service_units` | `nginx`, `docker`, `webmin`, `certbot.timer` | Units worth knowing about that are not containers |

## The JSON

| Field | Contents |
|-------|----------|
| `generated` | UTC timestamp of the snapshot |
| `host` | Hostname |
| `uptimeSeconds`, `load1`, `cores` | From `/proc/uptime`, `/proc/loadavg` and `nproc` |
| `memory.totalMb`, `memory.availableMb` | From `free -m` |
| `swap.totalMb`, `swap.usedMb` | Zero when there is no swap |
| `disks[]` | `{path, size, used, pct}` per `vitals_disk_paths`; bytes from `df -PB1` |
| `containers[]` | `{name, state, status, image}` from `docker ps -a`; empty when Docker is absent |
| `services[]` | `{name, state}` from `systemctl is-active`: `active`, `inactive` for a unit installed and stopped, `unknown` for one never installed — the page tells those two apart |
| `certificates[]` | `{name, days}`: days to expiry for each `/etc/letsencrypt/live/*`, to notice when automatic renewal has quietly stopped (slow half) |
| `backups[]` | `{name, ageHours}`: `name` is the parent directory (`n8n`, `espocrm`, `meshcentral`), `-1` when the directory holds no files (slow half) |
| `updates.pending`, `updates.security` | Counts from one `apt-get -s upgrade` simulation (slow half) |
| `updates.rebootRequired` | Whether `/var/run/reboot-required` exists |
| `slowAgeSeconds` | Age of the cached slow half |

Handlers: `Reload systemd`. A `Reload nginx` handler is defined too, but
nothing in this role notifies it — serving the file is the n8n role's job.
