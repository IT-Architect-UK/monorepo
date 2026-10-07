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
| `/etc/systemd/system/vps-vitals.service` | Oneshot unit that runs the fast half |
| `/etc/systemd/system/vps-vitals.timer` | `OnCalendar=<vitals_schedule>`, `OnBootSec=60`, `Persistent=true` |
| `/etc/systemd/system/vps-vitals-slow.service` | Oneshot unit that runs `vps-vitals.sh slow`, `TimeoutStartSec=600` so a stuck apt cannot pile up behind itself |
| `/etc/systemd/system/vps-vitals-slow.timer` | `OnCalendar=<vitals_slow_schedule>`, `OnBootSec=30`, `Persistent=true` |
| `/opt/vitals/vitals.json` | The snapshot, mode 0644. Written to a temp file and moved into place, so a reader never sees a half-written one |
| `/opt/vitals/cache/` | The slow half's cache, below |
| `/opt/vitals/runs.log` | One line per fast run (epoch, time, total ms, docker ms), trimmed to about two days. A run that never finished is logged with `-1` when the next run finds its `running` marker |
| `/opt/vitals/slow.log` | One line per slow run (epoch, time, total ms, certs ms, backups ms, apt ms), trimmed the same way |

The role writes the first snapshot immediately, so the page is not blank
until the timer first fires, and checks the file parses as JSON, so a
malformed script fails the playbook rather than silently blanking the page.

## Fast half, slow half

Memory, load, disks, containers and systemd units are cheap and are collected
every minute by `vps-vitals.sh`. Certificates, backup ages and pending
updates are expensive (`apt-get -s upgrade` alone parses the whole package
database, and on the VPS has taken minutes) and change on the scale of
hours, so `vps-vitals.sh slow` collects them on its own timer
(`vitals_slow_schedule`) into `vitals_dir/cache`, each file written whole and
moved into place, and the fast half only reads the cache. The two used to be
one run; a slow apt simulation then held the snapshot back past the
monitoring page's five-minute threshold and the watchdog emailed about it
every half hour. Now nothing the slow half does can delay the snapshot.
`slowAgeSeconds` in the output says how old the cache is: a large number
means the slow timer has stopped.

## Variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `vitals_dir` | `/opt/vitals` | Directory nginx serves from (world-readable; nothing in it is secret) |
| `vitals_file` | `/opt/vitals/vitals.json` | The snapshot |
| `vitals_schedule` | `*:0/1` (every minute) | systemd `OnCalendar` |
| `vitals_slow_schedule` | `*:0/15` (every fifteen minutes) | systemd `OnCalendar` for the slow half |
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
| `slowAgeSeconds` | Age of the slow half's cache |
| `runs` | How the script itself has behaved over the last 24 hours: `lastMs`, `count24h`, `slowest24h {at, ms, step}`, `gaps24h` and up to ten `gaps[] {after, minutes, runMs, step}` (a gap over two minutes between fast-half starts; a long `runMs` means the step named stalled, a short one means the timer did not fire), `recent[]` (the last six fast runs) and `slowHalf {last, count24h, slowest24h}` for the other timer. The monitoring page shows it as the "Snapshot runs" card and the watchdog attaches it to any email about the snapshot. `null` until the first run has been logged |

Handlers: `Reload systemd`. A `Reload nginx` handler is defined too, but
nothing in this role notifies it — serving the file is the n8n role's job.
