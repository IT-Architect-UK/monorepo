# CLAUDE.md — wmtx-arb-monitor

## What this project is
Read-only arbitrage monitor for WMTX (World Mobile Token) between
Cardano (Minswap, WMTX/ADA) and Base (Aerodrome). Polls DexScreener,
models executable prices at a configured trade size from pool reserves
(constant product), nets off fees, logs to CSV, alerts on threshold.

## Hard rules — do not violate without Darren's explicit approval
- Phase 0 is READ-ONLY. Never add private keys, wallet integration,
  signing, or trade execution to this codebase without explicit,
  per-change approval from Darren.
- Propose changes before making them; never mark work complete without
  running `python tests/test_monitor.py` and reporting the result honestly.
- Fee assumptions live in `FEES` in `src/wmtx_monitor.py`; changing them
  changes trade signals — call out any change explicitly.

## Layout
- `src/wmtx_monitor.py` — single-file monitor (argparse CLI)
- `tests/test_monitor.py` — mocked-API pipeline tests (plain script,
  exit code 0 = pass; no pytest dependency)
- `data/` — CSV spread logs (gitignored)

## Key implementation notes
- Pool selection: DexScreener `/latest/dex/search?q=WMTX`, filter
  chainId in {cardano, base}, baseToken.symbol == WMTX, pick max
  liquidity.usd per chain.
- Executable price: x*y=k on DexScreener `liquidity.base/quote`
  reserves. Known gap: if DexScreener omits reserves for the Cardano
  pair, the monitor warns and skips — planned fallback is Blockfrost.
- Quote-token USD price derived as priceUsd / priceNative.
- Environment: developed for Windows (Darren's machine); avoid
  Unix-only assumptions.
