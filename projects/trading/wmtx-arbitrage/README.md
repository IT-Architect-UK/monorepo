# WMTX Cross-Chain Arbitrage Monitor

Read-only monitor for World Mobile Token (WMTX) price spreads between
**Cardano (Minswap, WMTX/ADA)** and **Base (Aerodrome)**. Polls live pool
data, computes *executable* prices for a configured trade size — not spot
prices — nets off DEX fees, fixed costs, and a safety margin, then logs
every observation to CSV and alerts when the net spread in either
direction crosses a threshold.

> **Phase 0 scope: no wallets, no private keys, no trade execution.**
> Trade execution (Phase 1) is deliberately out of scope and requires
> separate, explicit approval before any code is added. See `CLAUDE.md`.

## Why executable prices matter

Aggregator spot prices routinely show WMTX gaps between chains that are
not capturable: the main Minswap pool holds roughly $1.4M of liquidity,
so slippage at realistic trade sizes erodes much of any apparent edge.
This monitor simulates the actual swap at your size against live
constant-product (x·y=k) reserves on both legs, in both directions, so an
alert means the gap survives slippage *and* fees.

## Contents

| Path | Purpose |
|------|---------|
| `src/wmtx_monitor.py` | Single-file monitor with CLI (poll, model, log, alert) |
| `tests/test_monitor.py` | Mocked-API pipeline tests — no network required |
| `CLAUDE.md` | Claude Code working rules and implementation context |
| `requirements.txt` | One dependency: `requests` |
| `data/` | CSV spread logs land here (gitignored) |

## Quick start

```bash
pip install -r requirements.txt
python src/wmtx_monitor.py --once                 # single check (smoke test)
python src/wmtx_monitor.py --size 2000            # continuous, $2,000 trade size
python src/wmtx_monitor.py --size 2000 --alert 2  # alert at >= 2% net (+0.5% safety margin)
```

| Option | Default | Meaning |
|--------|---------|---------|
| `--size` | `1000` | Trade size in USD used for slippage modelling |
| `--interval` | `20` | Poll interval in seconds |
| `--alert` | `1.0` | Net spread % that triggers an alert (safety margin added on top) |
| `--csv` | `wmtx_spreads.csv` | Observation log path |
| `--once` | off | Single check, then exit |

## How it works

1. **Discover pools** — queries the DexScreener search API for WMTX
   pairs and selects the deepest pool on each of Cardano and Base.
2. **Normalise to USD** — derives ADA/WETH/USDC prices from each pair's
   `priceUsd / priceNative`.
3. **Model both directions** — simulates buy-cheap/sell-rich at the
   configured size using pool reserves (x·y=k), Cardano→Base and
   Base→Cardano.
4. **Net off costs** — DEX fees (~0.3%/leg), fixed costs (Cardano
   batcher ≈ $2.50, Base gas ≈ $0.05) and a 0.5% safety margin. Tune
   these in the `FEES` dict at the top of `src/wmtx_monitor.py`.
5. **Log and alert** — every observation appended to CSV; terminal
   alert when net spread ≥ threshold.

## Tests

```bash
python tests/test_monitor.py   # exit code 0 = all pass; no pytest needed
```

Covers pool selection (deepest pool wins, junk pairs ignored), AMM math
direction and spot convergence, fee-adjusted P&L consistency in both
directions, CSV output, alert triggering, and graceful handling of
network errors and missing pools.

## Operational notes

- **Keep the CSV logs.** They are the paper-trading evidence for
  deciding whether Phase 1 (execution) is worth building, and the trade
  record for UK CGT if manual trades are made off the back of alerts —
  every crypto disposal is a taxable event.
- **Known gap:** if DexScreener omits `liquidity.base/quote` reserves
  for the Cardano pair, the monitor warns and skips rather than
  guessing. Planned fallback: read reserves directly via Blockfrost.
- The slippage model is first-order (ignores v3-style concentrated
  liquidity and batcher ordering effects on Cardano); treat outputs as
  estimates, not guarantees.

## Roadmap

- [x] Phase 0 — read-only spread monitor, CSV logging, threshold alerts
- [ ] Telegram/ntfy push alerts
- [ ] Blockfrost fallback for Cardano reserves
- [ ] Phase 1 — execution engine (**requires separate approval**:
      hot-wallet key management, per-trade limits, kill switch, audit log)

## Disclaimer

Market data may be stale or wrong; models are estimates; nothing in this
project constitutes financial advice.
