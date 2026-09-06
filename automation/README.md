# Automation

Infrastructure-as-code pipelines — the core of this repository.

| Directory | Purpose | Docs |
|-----------|---------|------|
| `packer/` | Golden image builds (Proxmox, VMware, AWS, Azure, GCP) and the Deployment Toolbox build | [packer/README.md](packer/README.md) |
| `ansible/` | Configuration management — roles, playbooks, inventory | [ansible/README.md](ansible/README.md) |
| `python/` | Operational tooling — inventory, health checks, metrics queries | [python/README.md](python/README.md) |
| `n8n/` | The IT Surgery booking, payment, CRM and monitoring workflows — the repo is the source of truth, deployed to the live instance on push | [n8n/README.md](n8n/README.md) |
| `calcom/` | Keeps Cal.com event types in step with the site's service catalogue | [calcom/README.md](calcom/README.md) |

New here? Start with the [Deployment Toolbox build](packer/builds/ubuntu-2404-automation-toolbox/README.md) — it produces the standing automation server everything else is deployed from.
