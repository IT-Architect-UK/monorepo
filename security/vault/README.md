# HashiCorp Vault

Deploys a Vault secrets server on Ubuntu. In the Deployment Toolbox architecture this runs on a **dedicated VM** (provisioned from the toolbox), so secrets survive toolbox rebuilds.

| File | Purpose |
|------|---------|
| `install-hashicorp-vault.sh` | Install the latest Vault from the HashiCorp apt repo: self-signed TLS, Raft storage, systemd service |
| `hashicorp-vault-server.sh` | Server configuration pass (see header for options) |
| `useful-commands.txt` | Operator crib sheet — init, unseal, secrets engines, policies |

## Quick start

```bash
sudo ./install-hashicorp-vault.sh
vault operator init        # SAVE the unseal keys and root token securely
vault operator unseal      # x3 — required again after every restart/reboot
```

**Vault starts sealed after every reboot** — it refuses all requests until unsealed with 3 of the 5 Shamir key shares from `init`. This is by design; see `useful-commands.txt`.
