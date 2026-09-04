# Projects

Self-contained project deployments — blockchain node infrastructure, a trading
analysis tool, and the business's websites. Each is standalone: it can be built,
run and understood on its own, without the rest of the monorepo. Usage details
live in each script's header or the project's own README.

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

`aya-testnet/` contains a numbered deployment sequence — run in order (`0.` info file first), plus `aya-testnet-monitor-blocks.sh` for block monitoring. `wmc/docker-node.sh` deploys a WMC Docker node.

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
| `web/itsurgery/` | IT Surgery — local IT support site for Penarth, Barry and Cardiff. Eleventy; 34 pages from shared layouts and structured data. Takes live bookings and deposits. |
| `web/it-architect/` | IT Architect — consultancy site covering cloud, infrastructure, security and applied AI. Eleventy; 13 pages. |
