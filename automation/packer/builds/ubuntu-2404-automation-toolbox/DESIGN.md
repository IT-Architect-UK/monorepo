# Deployment Toolbox — Architecture & Design

The Deployment Toolbox is the answer to a green-field problem: walking into a new
business or lab environment with nothing but a hypervisor and standing up a complete,
repeatable server-provisioning capability from a single repository.

One standing server — the toolbox — is built from this Packer template, cloned once,
and bootstrapped. From that point on, every server, appliance, and service in the
environment is created *from* the toolbox: functionally the role Altiris, LANDesk,
or SCCM played in traditional estates, built here entirely from open-source tooling.

Proxmox VE is the initial target platform; the build layout under
`automation/packer/builds/` is already structured for VMware, AWS, Azure, and GCP
expansion.

---

## Target Architecture

| Layer | Tool | Runs on | Status |
|---|---|---|---|
| Image building | Packer | Toolbox (baked) | ✅ Working |
| Configuration | Ansible (`common`, `monitoring-agent`, `tls` roles) | Toolbox (baked) | ✅ Working |
| Orchestration / primary web GUI | Semaphore | Toolbox (baked) | ✅ Working |
| Status dashboard / launcher | Homepage | Toolbox (baked) | ✅ Working |
| General admin | Webmin | Toolbox (baked) | ✅ Working |
| VM provisioning | Ansible `community.proxmox.proxmox_kvm` via Semaphore Survey | Toolbox | 🔨 Planned |
| Secrets | HashiCorp Vault | **Standalone server, provisioned by the toolbox** | 🔨 Planned |
| Inventory / CMDB | NetBox + Proxbox | TBD (toolbox or standalone) | 🔨 Planned |
| Monitoring | Prometheus + Grafana | TBD (toolbox or standalone) | 🔨 Planned |
| Container fleet visibility | Portainer CE + Agents | TBD (toolbox or standalone) | 🔨 Planned |

Toolbox VM sizing: **4 vCPU / 16 GB RAM** — sized for the full service set with headroom.

---

## Design Decisions

### 1. Composed stack, not a unified console

A single unified console (Foreman) was evaluated as the core platform: it offers
native PXE/bare-metal provisioning, Proxmox VM provisioning, and inventory in one
product. It was rejected on a verified blocker: Foreman's installer supports only
Ubuntu 22.04/20.04 and Debian 11 (confirmed against Foreman v3.12 docs, June 2026),
while the toolbox is deliberately pinned to Ubuntu 24.04 for Azure CLI / Docker /
HashiCorp repository parity. Changing the base OS to fit one tool was judged the
wrong trade.

The composed stack costs some integration work but keeps every component
independently replaceable, and each tool (Semaphore, Vault, NetBox, Prometheus,
Grafana, Portainer) is industry-recognized in its own right.

**Known gap:** physical/bare-metal provisioning is unsolved in the composed stack —
this is the direct cost of dropping Foreman. Revisit (MaaS, or Foreman on a dedicated
22.04 VM) when physical hardware is available to provision against.

### 2. Ansible-native provisioning — no Terraform

VM provisioning uses Ansible's `community.proxmox.proxmox_kvm` module directly,
driven by Semaphore Job Templates with Survey variables (hostname, template,
vCPU/RAM/disk, VLAN, role). Terraform was considered and dropped: it added a second
state model and toolchain for no benefit at this scale, since Ansible already owns
configuration and Semaphore already provides the execution UI.

### 3. Vault runs on a standalone server, not the toolbox

The toolbox is disposable by design — it is rebuilt from this template whenever it
improves. A secrets store must not be destroyed by a toolbox rebuild. Vault is
therefore deployed as the **first provisioned workload**, which also proves the
entire provisioning loop end-to-end (Semaphore Survey → playbook → new VM → Vault).

Day-0 bootstrap credentials (the Proxmox API token needed before Vault exists) live
in Semaphore's built-in encrypted Key Store; once Vault is up, secrets migrate there
and playbooks switch to `community.hashi_vault` lookups.

Vault uses standard Shamir seal with **manual unseal after reboot**, documented in
the login banner. Auto-unseal via cloud KMS is the upgrade path once a cloud platform
is in play — storing unseal keys on the same disk defeats the seal and is not done.

### 4. Install-time vs first-boot separation

Software **installs** are baked into the Packer template. Anything that generates
**state or secrets** (Semaphore admin, service credentials, Vault init) happens in a
post-clone bootstrap step, never at image build time — no secrets are ever baked into
a template or leaked into build logs. Green-field flow: `packer build` → clone →
bootstrap → working toolbox.

### 5. Per-environment variable files

Everything site-specific (Proxmox host/node, storage pool, VLAN, IP addressing,
VM IDs/names) lives in `pkrvars` environment files (see `../../environments/`).
Deploying the same repo into a new environment means writing one new var-file —
nothing else changes.

### 6. Repository conventions

- Every tool installs via a standalone `applications/<tool>/install-<tool>.sh` using
  plain `docker run` — no docker-compose. Canonical style reference:
  `applications/webmin/install-webmin.sh`.
- Install scripts are wired into the build via `provisioner "shell"` blocks in the
  `.pkr.hcl` — a script that exists but isn't wired in does nothing.

---

## Roadmap

1. **Post-clone bootstrap script** — Semaphore admin init, Proxmox credential into
   Semaphore Key Store, credential/URL summary via banner and Homepage.
2. **`provision_vm.yml`** + Semaphore Job Template with Survey variables.
3. **Vault server** as the first provisioned workload (install scripts exist:
   `security/vault/`); wire `community.hashi_vault` lookups.
4. **NetBox + Proxbox** — provisioning playbook registers every new VM; becomes
   Ansible dynamic inventory.
5. **Prometheus + Grafana** — fold the `monitoring-agent` role into baseline
   provisioning so every new VM auto-enrolls.
6. **Portainer** — server plus Agent rollout via the `common` role.
7. Firewall (`setup-iptables.sh` / `common` role) updates for new service ports.
8. End-to-end proof: green-field deployment of a real server through the full loop.
