# Projects

Self-contained project deployments — currently blockchain node infrastructure. These demonstrate end-to-end node deployment: baseline OS config, service installation, firewalling, and monitoring. Usage details in each script's header.

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

Read-only WMTX (World Mobile Token) arbitrage monitor between Cardano
(Minswap) and Base (Aerodrome). Models executable prices at a configured
trade size from live pool reserves, nets off fees, logs spreads to CSV,
and alerts on capturable gaps. No keys, no execution — see the project
README for scope and roadmap.

| File | Purpose |
|------|---------|
| `src/wmtx_monitor.py` | Spread monitor CLI (poll · model · log · alert) |
| `tests/test_monitor.py` | Offline pipeline tests (mocked market data) |
