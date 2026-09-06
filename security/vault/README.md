# HashiCorp Vault

Deploys a Vault secrets server on Ubuntu. In the Deployment Toolbox architecture this runs on a **dedicated VM** (provisioned from the toolbox), so secrets survive toolbox rebuilds.

| File | Purpose |
|------|---------|
| `install-hashicorp-vault.sh` | Install the latest Vault from the HashiCorp apt repo: self-signed TLS, Raft storage, systemd service |
| `hashicorp-vault-server.sh` | Legacy host baseline runner for a Vault VM: disables cloud-init, then runs a fixed list of scripts (branding, Webmin, extend-disks, IPv6, DNS, iptables, root CA, `install-hashicorp-vault.sh`) from `CONFIG_SCRIPTS_DIR`, upgrades and offers a reboot. Interactive (proceed and reboot prompts). See Known issue |
| `useful-commands.txt` | Operator crib sheet — init, unseal, secrets engines, policies |

## Quick start

```bash
sudo ./install-hashicorp-vault.sh
vault operator init        # SAVE the unseal keys and root token securely
vault operator unseal      # x3 — required again after every restart/reboot
```

**Known issue:** `hashicorp-vault-server.sh` resolves its script list under
`/source-files/github/monorepo/scripts/bash/ubuntu` (overridable with
`CONFIG_SCRIPTS_DIR`), a layout this repo no longer has, and exits at the first
script it cannot find. Use `install-hashicorp-vault.sh` directly, with
`infrastructure/servers/linux/configuration/server-baseline.sh` for the host
baseline.

**Vault starts sealed after every reboot** — it refuses all requests until unsealed with 3 of the 5 Shamir key shares from `init`. This is by design; see `useful-commands.txt`.
