# Projects

Self-contained project deployments — blockchain node infrastructure, a trading
analysis tool, and the business's websites. Each is standalone: it can be built,
run and understood on its own, without the rest of the monorepo. Usage details
live in each script's header or the project's own README.

> **Archived.** The blockchain node scripts below are kept as a record of past
> work. No node is running, they are not maintained and they are not to be
> modernised. `blockchain/README.md` has the full script listing.

## Cardano — `blockchain/cardano/`

| Script | Purpose |
|--------|---------|
| `install-cardano-node-baseline.sh` | Baseline OS prep for a Cardano node |
| `deploy-docker-cardano-relay.sh` | Cardano relay node + Prometheus via Docker (opens port 3001) |
| `configure-cardano-node-iptables.sh` | Node firewall rules |
| `download-cardano-cli.sh` | Fetch the Cardano CLI tools |

## COTI — `blockchain/coti/`

| Script | Purpose |
|--------|---------|
| `install-coti-node-baseline.sh` | Baseline OS prep for a COTI node |
| `configure-coti-iptables.sh` | Node firewall rules |

## World Mobile — `blockchain/world-mobile/`

`aya-testnet/` is a numbered sequence, run in order:

| File | Purpose |
|------|---------|
| `0. aya-testnet-useful-info.txt` | Reference notes: `aya-node` service commands, RPC and websocket endpoints, faucet and explorer links |
| `1. aya-testnet-node-deploy.sh` | Baseline OS prep and dependencies, opens P2P port 30333, creates the node user |
| `2. aya-testnet-node-configuration.sh` | Downloads the `aya-node` release and chain spec, writes the session-key split helper and the `aya-node` systemd service |
| `3. aya-testnet-node-keys.sh` | Generates and inserts the AURA, GRANDPA and ImOnline keys, then rotates the session keys over RPC |
| `aya-testnet-monitor-blocks.sh` | Follows new blocks over local RPC and names the node that produced each one |

`wmc/`:

| Script | Purpose |
|--------|---------|
| `docker-node.sh` | Baseline OS prep for a World Mobile Chain Docker node (Webmin, Docker, Portainer agent, firewall), then upgrades and reboots |

## Trading — `trading/wmtx-arbitrage/`

> **Paused (2026-09-04).** Not under active development; left as-is and
> excluded from the current review and test work.

Read-only WMTX (World Mobile Token) arbitrage monitor between Cardano
(Minswap) and Base (Aerodrome). Models executable prices at a configured
trade size from live pool reserves, nets off fees, logs spreads to CSV,
and alerts on capturable gaps. No keys, no execution — see the project
README for scope and roadmap.

| File | Purpose |
|------|---------|
| `src/wmtx_monitor.py` | Spread monitor CLI (poll · model · log · alert) |
| `tests/test_monitor.py` | Offline pipeline tests (mocked market data) |

## Web — `web/`

Static websites for the business's trading brands, deployed to Netlify from this
repo. See `web/README.md` for conventions.

| Project | Purpose |
|---------|---------|
| `web/itsurgery/` | IT Surgery — local IT support site for Penarth, Barry and Cardiff. Eleventy; 40 pages from shared layouts and structured data. Takes live bookings and deposits. |
| `web/it-architect/` | IT Architect — consultancy site covering cloud, infrastructure, security and applied AI. Eleventy; 13 pages. |
