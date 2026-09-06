# Utilities

Small helper scripts. Usage in each header.

| Script | Purpose |
|--------|---------|
| `git-clone.ps1` | Windows bootstrap: installs Chocolatey (pinned, SHA256-checked) and git if missing, installs the PackageManagement and PendingReboot modules, then deletes any existing clone and re-clones the repository to `D:\Git\<owner>\<repo>` (or `C:\`). Logs under `<drive>\Logs\`. See Known issues |
| `github-monorepo-download.sh` | VMware guest-customisation helper: installs git, clones this repo to `/source-files/github/monorepo` (or pulls if present), adds an `@reboot` crontab entry for itself, `apt-get upgrade`s and reboots if required. Logs to `/logs/vmware-customisation-github-clone.log`. See Known issues |
| `make-sh-executable.sh` | Recursively `chmod +x` every `.sh` under a given directory — handy after checkout on a fresh host |

## Known issues

- `git-clone.ps1` has no `param()` block: the repository URL is hard-coded to
  `https://github.com/IT-Surgery/scripts.git` (not this repo), so the
  `-repoUrl` parameter and the `UpdateGitRepo.ps1` examples in its help text do
  not apply. Edit `$repoUrl` before use.
- `github-monorepo-download.sh` `cd`s into
  `scripts/bash/ubuntu/{configuration,server-roles,packages}` after the clone;
  those paths no longer exist in this repo, so the script exits before the
  upgrade step. Prefer `infrastructure/servers/linux/configuration/sync-monorepo.sh`.
