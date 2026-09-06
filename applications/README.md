# Applications

Standalone installers for self-hosted applications. Each script is self-contained: run it on the target server and it installs, configures, and verifies the application. Full usage details, prerequisites, and configuration options are documented in each script's header.

All scripts target Ubuntu 24.04 unless noted. Docker-based installers assume Docker CE is already installed (see `containers/docker/`).

| Script | Application | Method |
|--------|-------------|--------|
| `awx/install-awx.sh` | AWX (Ansible web UI) on Minikube via AWX Operator 2.19.1 — needs 8 CPU / 16 GB RAM. See Known issue | Kubernetes |
| `bacula/install-bacula.sh` | Bacula backup server (Director, Storage & File daemons), optional Bacularis web UI | apt |
| `homepage/install-homepage.sh` | Homepage status dashboard (gethomepage.dev) on port 3002 — the Deployment Toolbox launcher page | Docker |
| `webmin/install-webmin.sh` | Webmin server administration UI on port 10000. Repo setup script pinned to a release tag (`WEBMIN_SETUP_TAG`) and SHA256-checked, never fetched from master | apt (vendor repo) |
| `wordpress/install-wordpress.sh` | WordPress on a LAMP stack (`apache2`, `mysql-server`, PHP) with an Apache vhost. Prompts for the database password | apt |

## Usage

```bash
sudo ./applications/<app>/install-<app>.sh
```

Most installers write a timestamped log (path shown at the end of the run) and finish with a summary including the URL and any generated credentials. The WordPress installer is the exception: it logs to `/logs/wordpress_installation.log` and ends with a completion line only.

**Known issue:** `awx/install-awx.sh` clones the AWX Operator into
`/source-files/github/monorepo/scripts/bash/ubuntu/packages`, a layout this
repo no longer has; the directory must exist (and be writable) or the script
exits at its write-permission check. Create it first, or edit `WORKDIR`.
