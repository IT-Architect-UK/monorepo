# Applications

Standalone installers for self-hosted applications. Each script is self-contained: run it on the target server and it installs, configures, and verifies the application. Full usage details, prerequisites, and configuration options are documented in each script's header.

All scripts target Ubuntu 24.04 unless noted. Docker-based installers assume Docker CE is already installed (see `containers/docker/`).

| Script | Application | Method |
|--------|-------------|--------|
| `awx/install-awx.sh` | AWX (Ansible web UI) on Minikube via AWX Operator — needs 8 CPU / 16 GB RAM | Kubernetes |
| `bacula/install-bacula.sh` | Bacula backup server (Director, Storage & File daemons), optional Bacularis web UI | apt |
| `homepage/install-homepage.sh` | Homepage status dashboard (gethomepage.dev) on port 3002 — the Deployment Toolbox launcher page | Docker |
| `webmin/install-webmin.sh` | Webmin server administration UI on port 10000 | apt (vendor repo) |
| `wordpress/install-wordpress.sh` | WordPress with MySQL | Docker |

## Usage

```bash
sudo ./applications/<app>/install-<app>.sh
```

Every installer writes a timestamped log (path shown at the end of the run) and finishes with a summary including the URL and any generated credentials.
