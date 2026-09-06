# Blockchain node scripts

> **Archived.** These scripts deployed Cardano, COTI and World Mobile nodes on
> Ubuntu servers; the dated headers run from December 2024 to April 2025.
> Nothing is running now. They are kept as a record of the work and are
> **not** maintained or to be modernised. CI still checks that they parse and
> lint; nothing exercises them.

Each script was run on the target server from a checkout of this repository
at `/source-files/github/monorepo`. The baseline scripts call shared Ubuntu
helpers (Webmin, disk extension, DNS, iptables, Docker, Portainer agent,
cloud-init off) from a `scripts/bash/ubuntu/` directory that no longer exists:
those helpers have since moved under `applications/` and `infrastructure/`, so
the scripts would need their paths updating before they could run again.
Details are in each script's header.

## Cardano — `cardano/`

| Script | Purpose |
|--------|---------|
| `install-cardano-node-baseline.sh` | Baseline OS prep for a Cardano node: runs the shared Ubuntu helpers, full upgrade, reboot |
| `configure-cardano-node-iptables.sh` | Firewall rules: private subnets, plus TCP 6000 for the node |
| `deploy-docker-cardano-relay.sh` | Cardano relay node (`ghcr.io/blinklabs-io/cardano-node`) and Prometheus via Docker; opens TCP 3001 |
| `download-cardano-cli.sh` | Fetches the latest `cardano-cli` Linux x86_64 release from GitHub |

## COTI — `coti/`

| Script | Purpose |
|--------|---------|
| `install-coti-node-baseline.sh` | Baseline OS prep for a COTI node: the same helper sequence, full upgrade, reboot |
| `configure-coti-iptables.sh` | Firewall rules: private subnets, plus TCP 8545, 8546 and TCP/UDP 7400 for the node |

## World Mobile — `world-mobile/`

### `aya-testnet/` — run in numbered order

| File | Purpose |
|------|---------|
| `0. aya-testnet-useful-info.txt` | Reference notes, not a script: `aya-node` service commands, block-production and health checks, RPC and websocket endpoints, faucet and explorer links |
| `1. aya-testnet-node-deploy.sh` | Baseline OS prep and dependencies (`curl`, `jq`, `cargo`), opens P2P port TCP 30333, creates the node user |
| `2. aya-testnet-node-configuration.sh` | Downloads the `aya-node` release binary and devnet chain spec, writes the session-key split helper and the `aya-node` systemd service, enables it |
| `3. aya-testnet-node-keys.sh` | Generates the node keys, inserts the AURA, GRANDPA and ImOnline keys into the keystore, then rotates the session keys over local RPC |
| `aya-testnet-monitor-blocks.sh` | Polls the local RPC for new blocks every five seconds, decodes the block author and says whether it was this node (needs `jq`, `xxd`, `subwasm`) |

### `wmc/`

| Script | Purpose |
|--------|---------|
| `docker-node.sh` | Baseline OS prep for a World Mobile Chain Docker node: shared helpers (Webmin, Docker, Portainer agent, firewall), full upgrade, reboot |
