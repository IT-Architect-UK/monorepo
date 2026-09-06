# monitoring-agent role

Installs Prometheus `node_exporter`, so a Prometheus server can scrape host
metrics (CPU, memory, disk, network, filesystem, processes, systemd units)
from `http://<host>:9100/metrics` and Grafana can chart them. Applied by
`playbooks/deploy-monitoring.yml` to `target_hosts` (default `all`).

## What it does

1. Creates a `node_exporter` system user with no shell and no home directory
2. Downloads `node_exporter-<version>.linux-amd64.tar.gz` from the GitHub
   release into `/tmp`, extracts it, and installs the binary to
   `/usr/local/bin/node_exporter`
3. Writes `/etc/systemd/system/node_exporter.service`, running as that user
   with `--collector.systemd --collector.processes` and `Restart=on-failure`
4. Enables and starts the service
5. Opens TCP 9100 with `community.general.ufw` on Debian-family hosts
6. Checks `http://localhost:9100/metrics` answers 200

## Variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `node_exporter_version` | `1.8.1`, set in `tasks/main.yml` (the role has no `defaults/`) | Release to download; override with `-e` or in the inventory |

The download is not checksummed, and the archive name is fixed to
`linux-amd64`.

## Known issues

- Two tasks notify `Restart node_exporter`, but the role has no `handlers/`
  directory, so there is no such handler. Ansible reports a missing handler
  as an error once the notifying task changes, which is the run that installs
  or updates the binary or the unit. A re-run finds both unchanged and
  completes.
- The firewall step uses `ufw`, while every other host in this repo is built
  on iptables (`common` role, `setup-iptables.sh`). Nothing here installs the
  `ufw` package, and on a host running the iptables baseline the two rulesets
  know nothing of each other. The consistent fix is
  `firewall_extra_rules: [{ port: 9100, proto: tcp }]` in the inventory,
  which the `common` role applies and fingerprints
  ([Firewall](../../README.md#-firewall)).
