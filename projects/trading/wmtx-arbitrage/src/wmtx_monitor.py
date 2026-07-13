#!/usr/bin/env python3
"""
WMTX Cross-Chain Arbitrage Monitor (Phase 0 - read-only, no keys, no execution)

Polls DexScreener for the deepest WMTX pools on Cardano and Base, computes
EXECUTABLE prices for a configured trade size (constant-product slippage
estimate from live reserves), subtracts fees, and reports the net spread in
both directions. Logs every observation to CSV and alerts when the net
spread exceeds the configured threshold.

Usage:
    pip install requests
    python wmtx_monitor.py                    # run with defaults
    python wmtx_monitor.py --size 2000        # $2,000 trade size
    python wmtx_monitor.py --interval 15      # poll every 15s
    python wmtx_monitor.py --once             # single check, then exit

No wallet, no private keys, no trades. Read-only market data.
"""

import argparse
import csv
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: pip install requests")

DEXSCREENER_SEARCH = "https://api.dexscreener.com/latest/dex/search?q=WMTX"

# ----------------------------- fee model ------------------------------------
# Conservative defaults. Adjust to reality as you observe actual costs.
FEES = {
    "cardano_dex_fee_pct": 0.30,   # Minswap swap fee %
    "cardano_fixed_usd": 2.50,     # batcher + network fee (~2 ADA + tx fee)
    "base_dex_fee_pct": 0.30,      # Aerodrome volatile pool fee %
    "base_fixed_usd": 0.05,        # Base gas, generous
    "safety_margin_pct": 0.50,     # extra buffer for price movement/estimate error
}


@dataclass
class Pool:
    chain: str
    dex: str
    pair_address: str
    price_usd: float          # spot price of WMTX in USD
    quote_symbol: str
    reserve_wmtx: float       # base token reserves
    reserve_quote: float      # quote token reserves
    quote_price_usd: float    # USD price of the quote token (ADA, WETH, USDC...)
    liquidity_usd: float
    volume_h24: float
    updated_at_ms: int = 0   # DexScreener pairCreatedAt/updatedAt when present


def fetch_pools(session: requests.Session) -> dict:
    """Fetch WMTX pairs and return the deepest pool per target chain."""
    r = session.get(DEXSCREENER_SEARCH, timeout=15,
                    params={"_ts": int(time.time() * 1000)},
                    headers={"Cache-Control": "no-cache", "Pragma": "no-cache"})
    r.raise_for_status()
    pairs = r.json().get("pairs") or []
    return select_pools(pairs)


def select_pools(pairs: list) -> dict:
    """Pick the highest-liquidity WMTX pool on each target chain."""
    best = {}
    for p in pairs:
        try:
            chain = p.get("chainId")
            if chain not in ("cardano", "base"):
                continue
            if (p.get("baseToken") or {}).get("symbol", "").upper() != "WMTX":
                continue
            liq = p.get("liquidity") or {}
            liq_usd = float(liq.get("usd") or 0)
            if liq_usd <= 0:
                continue
            price_usd = float(p.get("priceUsd") or 0)
            price_native = float(p.get("priceNative") or 0)
            if price_usd <= 0 or price_native <= 0:
                continue
            pool = Pool(
                chain=chain,
                dex=p.get("dexId", "?"),
                pair_address=p.get("pairAddress", "?"),
                price_usd=price_usd,
                quote_symbol=(p.get("quoteToken") or {}).get("symbol", "?"),
                reserve_wmtx=float(liq.get("base") or 0),
                reserve_quote=float(liq.get("quote") or 0),
                quote_price_usd=price_usd / price_native,
                liquidity_usd=liq_usd,
                volume_h24=float((p.get("volume") or {}).get("h24") or 0),
                updated_at_ms=int(p.get("updatedAt") or 0),
            )
            if pool.reserve_wmtx <= 0 or pool.reserve_quote <= 0:
                continue
            if chain not in best or pool.liquidity_usd > best[chain].liquidity_usd:
                best[chain] = pool
        except (TypeError, ValueError):
            continue
    return best


# ------------------------ executable price math ------------------------------
# Constant-product (x*y=k) estimate. Minswap v2 and Aerodrome volatile pools
# are both x*y=k style, so this is a reasonable first-order model. Fees are
# applied separately in the spread calc, so these functions are fee-exclusive.

def buy_wmtx(pool: Pool, usd_in: float) -> tuple[float, float]:
    """Spend usd_in (in quote token) to buy WMTX. Returns (wmtx_out, eff_price_usd)."""
    quote_in = usd_in / pool.quote_price_usd
    k = pool.reserve_wmtx * pool.reserve_quote
    wmtx_out = pool.reserve_wmtx - k / (pool.reserve_quote + quote_in)
    if wmtx_out <= 0:
        return 0.0, float("inf")
    return wmtx_out, usd_in / wmtx_out


def sell_wmtx(pool: Pool, wmtx_in: float) -> tuple[float, float]:
    """Sell wmtx_in for quote token. Returns (usd_out, eff_price_usd)."""
    k = pool.reserve_wmtx * pool.reserve_quote
    quote_out = pool.reserve_quote - k / (pool.reserve_wmtx + wmtx_in)
    usd_out = quote_out * pool.quote_price_usd
    if wmtx_in <= 0:
        return 0.0, 0.0
    return usd_out, usd_out / wmtx_in


def direction_pnl(buy_pool: Pool, sell_pool: Pool, usd_size: float,
                  buy_fee_pct: float, sell_fee_pct: float,
                  fixed_usd: float) -> dict:
    """Buy on buy_pool, sell same tokens on sell_pool. Net of all fees."""
    usd_after_buy_fee = usd_size * (1 - buy_fee_pct / 100)
    wmtx, buy_px = buy_wmtx(buy_pool, usd_after_buy_fee)
    gross_out, sell_px = sell_wmtx(sell_pool, wmtx)
    usd_out = gross_out * (1 - sell_fee_pct / 100) - fixed_usd
    profit = usd_out - usd_size
    return {
        "wmtx": wmtx,
        "buy_eff_px": buy_px,
        "sell_eff_px": sell_px,
        "profit_usd": profit,
        "net_pct": (profit / usd_size) * 100 if usd_size else 0.0,
    }


def analyse(pools: dict, usd_size: float) -> dict:
    car, base = pools["cardano"], pools["base"]
    fixed = FEES["cardano_fixed_usd"] + FEES["base_fixed_usd"]
    return {
        "spot_cardano": car.price_usd,
        "spot_base": base.price_usd,
        "spot_gap_pct": (base.price_usd / car.price_usd - 1) * 100,
        "car_to_base": direction_pnl(car, base, usd_size,
                                     FEES["cardano_dex_fee_pct"],
                                     FEES["base_dex_fee_pct"], fixed),
        "base_to_car": direction_pnl(base, car, usd_size,
                                     FEES["base_dex_fee_pct"],
                                     FEES["cardano_dex_fee_pct"], fixed),
    }


# ------------------------------ reporting -----------------------------------
CSV_FIELDS = ["utc_time", "spot_cardano", "spot_base", "spot_gap_pct",
              "size_usd",
              "car_to_base_net_pct", "car_to_base_profit_usd",
              "base_to_car_net_pct", "base_to_car_profit_usd",
              "small_size_usd", "small_best_net_pct",
              "cardano_pair", "base_pair",
              "cardano_data_age_s", "base_data_age_s",
              "cardano_liq_usd", "base_liq_usd", "stale", "alert"]


def log_csv(path: str, row: dict):
    new = not os.path.exists(path)
    with open(path, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        if new:
            w.writeheader()
        w.writerow(row)


_last_snapshot = {}


def data_age_s(pool: Pool) -> float:
    """Seconds since DexScreener last updated this pair (-1 if unknown)."""
    if pool.updated_at_ms <= 0:
        return -1.0
    return round(time.time() - pool.updated_at_ms / 1000, 1)


def run_once(session, usd_size, alert_pct, csv_path, small_size=500.0) -> bool:
    global _last_snapshot
    pools = fetch_pools(session)
    missing = [c for c in ("cardano", "base") if c not in pools]
    if missing:
        print(f"[{ts()}] WARN: no WMTX pool found on: {', '.join(missing)} — skipping")
        return False

    a = analyse(pools, usd_size)
    c2b, b2c = a["car_to_base"], a["base_to_car"]
    best = max(c2b["net_pct"], b2c["net_pct"])
    alert = best >= alert_pct

    # Small-size comparison (slippage sanity check at lower capital)
    a_small = analyse(pools, small_size)
    small_best = max(a_small["car_to_base"]["net_pct"],
                     a_small["base_to_car"]["net_pct"])

    # Staleness detector: identical reserves+prices to previous poll = stale
    snapshot = tuple((p.chain, p.price_usd, p.reserve_wmtx, p.reserve_quote)
                     for p in sorted(pools.values(), key=lambda x: x.chain))
    stale = snapshot == _last_snapshot.get("snap")
    _last_snapshot["snap"] = snapshot
    if stale:
        _last_snapshot["count"] = _last_snapshot.get("count", 0) + 1
    else:
        _last_snapshot["count"] = 0
    stale_runs = _last_snapshot["count"]

    print(f"[{ts()}] Cardano ${a['spot_cardano']:.5f} | Base ${a['spot_base']:.5f} "
          f"| spot gap {a['spot_gap_pct']:+.2f}%")
    print(f"  Cardano→Base: net {c2b['net_pct']:+.2f}% (${c2b['profit_usd']:+.2f}) "
          f"buy@{c2b['buy_eff_px']:.5f} sell@{c2b['sell_eff_px']:.5f}")
    print(f"  Base→Cardano: net {b2c['net_pct']:+.2f}% (${b2c['profit_usd']:+.2f}) "
          f"buy@{b2c['buy_eff_px']:.5f} sell@{b2c['sell_eff_px']:.5f}")
    if alert:
        print(f"  *** ALERT: net spread {best:+.2f}% >= {alert_pct}% threshold ***\a")
    print(f"  @${small_size:.0f}: best net {small_best:+.2f}% | "
          f"data age car {data_age_s(pools['cardano'])}s / base {data_age_s(pools['base'])}s"
          + (f" | STALE x{stale_runs} — identical data since last poll" if stale else ""))
    if stale and stale_runs in (3, 15, 45, 90):
        print(f"  !!! WARNING: market data unchanged for {stale_runs} consecutive polls — "
              f"DexScreener may be serving cached/stale data !!!")

    log_csv(csv_path, {
        "utc_time": ts(),
        "small_size_usd": small_size,
        "small_best_net_pct": round(small_best, 3),
        "cardano_pair": pools["cardano"].pair_address[:24],
        "base_pair": pools["base"].pair_address[:24],
        "cardano_data_age_s": data_age_s(pools["cardano"]),
        "base_data_age_s": data_age_s(pools["base"]),
        "stale": stale,
        "spot_cardano": round(a["spot_cardano"], 6),
        "spot_base": round(a["spot_base"], 6),
        "spot_gap_pct": round(a["spot_gap_pct"], 3),
        "size_usd": usd_size,
        "car_to_base_net_pct": round(c2b["net_pct"], 3),
        "car_to_base_profit_usd": round(c2b["profit_usd"], 2),
        "base_to_car_net_pct": round(b2c["net_pct"], 3),
        "base_to_car_profit_usd": round(b2c["profit_usd"], 2),
        "cardano_liq_usd": round(pools["cardano"].liquidity_usd),
        "base_liq_usd": round(pools["base"].liquidity_usd),
        "alert": alert,
    })
    return alert


def ts() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def main():
    ap = argparse.ArgumentParser(description="WMTX Cardano<->Base arbitrage monitor")
    ap.add_argument("--size", type=float, default=1000.0, help="trade size in USD (default 1000)")
    ap.add_argument("--interval", type=int, default=20, help="poll interval seconds (default 20)")
    ap.add_argument("--alert", type=float, default=1.0, help="alert threshold net %% (default 1.0)")
    ap.add_argument("--csv", default="wmtx_spreads.csv", help="CSV log path")
    ap.add_argument("--once", action="store_true", help="single check then exit")
    args = ap.parse_args()

    # Includes safety margin in the effective alert bar
    effective_alert = args.alert + FEES["safety_margin_pct"]
    print(f"WMTX monitor | size ${args.size:.0f} | alert at net >= {effective_alert}% "
          f"(incl. {FEES['safety_margin_pct']}% safety margin) | log: {args.csv}")
    print("Read-only. No keys, no execution.\n")

    session = requests.Session()
    session.headers["User-Agent"] = "wmtx-monitor/0.2"

    while True:
        try:
            run_once(session, args.size, effective_alert, args.csv)
        except requests.RequestException as e:
            print(f"[{ts()}] network error: {e}")
        except Exception as e:
            print(f"[{ts()}] error: {e}")
        if args.once:
            break
        time.sleep(max(5, args.interval))


if __name__ == "__main__":
    main()
