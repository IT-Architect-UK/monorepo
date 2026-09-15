# Monitoring page: Containers card overflows, and find out why every container keeps restarting

Status: done (code); restart cause needs commands run on the VPS
Owner: Claude Code

## Context

dashboard.itsurgery.me/monitoring is rendered by the n8n workflow
`automation/n8n/workflows/monitoring.json`, node "Build the page"
(jsCode). Data comes from the VPS vitals snapshot written by
`automation/ansible/roles/vitals/templates/vitals.sh.j2`, which passes
`docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}|{{.Image}}'`
straight through as `containers[].status`.

**Problem 1 - layout.** In the jsCode CSS, `td.r{text-align:right;
white-space:nowrap}` (line ~254). The Containers table (line ~322) puts the
raw Docker status in a `td.r`. When Docker says
`Up Less than a second (health: starting)` the cell cannot wrap, so the
name column is crushed (`oauth2-proxy`, `n8n-postgres`, `espocrm-daemon`,
`espocrm-db` wrap onto two lines) and the text runs past the right edge of
the 300px card (`.cards{columns:300px}`). Seen by Darren 2026-09-14
(screenshot) and reproducible whenever a container has just started or has
a health check.

**Problem 2 - restarts.** Darren's screenshot showed all 7 containers "Up
Less than a second"; Cowork's check a while later (2026-09-14, page text)
showed all 7 "Up 3 minutes". Host load 0.07, 0 updates pending, backups
17-18 h old. Either Docker/the host restarted twice, or containers are
being restarted on a schedule (unattended-upgrades restarting containerd,
a cron `docker compose restart`, the backup job, OOM, or a reboot). The
page has no host-uptime figure, so this cannot be told apart from the page.

## Do this

1. In "Build the page":
   - Stop passing raw Docker status to the UI. Add a `containerLabel(c)`
     that turns `Up Less than a second` into `just started`, `Up 3 minutes`
     into `up 3 min`, `Up 2 hours` into `up 2 h`, `Up 5 days` into
     `up 5 d`, and strips the `(healthy)` suffix.
   - Use the health in the dot instead of the text: `(health: starting)`
     -> amber dot, `(unhealthy)` -> red dot, otherwise as now
     (`running` -> green, anything else -> red). Today `state === 'running'`
     is green even when unhealthy (line ~75) - fix that. The Diagnostics
     list (line ~356) should carry the same label and state.
   - Let the right-hand cell wrap when it must: keep `nowrap` for the
     short numeric cells but give the Containers/Backups tables' `td.r`
     `white-space:normal; overflow-wrap:anywhere; max-width:55%`, and give
     the name cell `overflow-wrap:anywhere`. Nothing may overflow a 300px
     card at the default font size.
2. Add host uptime to "The server" card (vitals.sh: `uptime -s` or
   `/proc/uptime`; jsCode: `up 12 d 4 h`) so a reboot is visible.
3. Find the restart cause. On the VPS (Ansible-on-the-box pattern; if you
   cannot reach it, say so in Result and Cowork/Darren will run the
   commands through Webmin):
   `uptime`, `docker events --since 72h --filter type=container
   --filter event=start --filter event=die --format '{{.Time}} {{.Actor.Attributes.name}} {{.Action}}'`,
   `journalctl -u docker --since "72 hours ago" | tail -50`,
   `grep -i -E 'docker|containerd|reboot' /var/log/unattended-upgrades/unattended-upgrades.log | tail`,
   `last reboot | head`, and `crontab -l` for root plus
   `/etc/cron.d/*`. Write what you find in Result. Do not change restart
   policy or timers without a further handoff - report first.
4. Deploy the workflow the usual way (whatever "Last deploy" runs for n8n),
   reload dashboard.itsurgery.me/monitoring, and confirm: the Containers
   card renders on one line per container with no overflow at 300px card
   width, and "The server" shows host uptime. Screenshot or page text in
   Result. Commit and push.

## Result

Claude Code, 2026-09-15. `monitoring.json` "Build the page" only; the
vitals script already reports `uptimeSeconds`, so no Ansible change.

1. Docker's status text no longer reaches the page. `containerLabel()`
   gives `just started`, `up 3 min`, `up 2 h`, `up 5 d`, `up 2 wk`,
   `exited (1) 3 min ago`, `restarting`; the `(healthy)` /
   `(health: starting)` / `(unhealthy)` suffix is stripped. Health drives
   the dot: starting = amber, unhealthy = red (a running-but-unhealthy
   container was green before), not running = red. The JSON the watchdog
   reads carries the same label and state, and a `host uptime` part.
2. "The server" card has an Uptime row (`up 3 d 4 h`).
3. Layout: the Containers and Backups tables get `class="wrap"`: the name
   column is 58% wide, the right-hand cell may wrap, every cell has
   `overflow-wrap:anywhere`. The short numeric cells elsewhere keep
   `nowrap`. Rendered locally with seven containers in every state
   (starting, healthy, unhealthy, exited, "About an hour", "2 weeks")
   inside a 309px card: card scrollWidth equals clientWidth, no cell
   crosses the card edge, every running container is one line; only
   `exited (1) 3 min ago` wraps to two.
4. Restart cause: not found from here. Claude Code has no route to the
   VPS, and nothing in the repo restarts containers on a schedule: the
   three backup timers only dump and copy, the compose files use
   `restart: unless-stopped` / `always`, and no cron or timer runs
   `docker compose`. All seven starting within the same second points at
   the Docker daemon restarting (a docker-ce or containerd package
   upgrade by unattended-upgrades does that, and `live-restore` is not
   set) or at a host reboot; the new Uptime row tells those two apart
   next time. Cowork/Darren: run the commands in step 3 through Webmin
   and paste the output here. Deployed by the push of this commit
   (`deploy-n8n.yml`); the live page check is Cowork's.

