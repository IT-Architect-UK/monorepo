"""Verify wmtx_monitor pipeline with mocked DexScreener data (no network)."""
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from unittest.mock import patch, MagicMock
import wmtx_monitor as m

# Realistic mock: Cardano pool cheaper ($0.0589), Base pool higher ($0.0630)
MOCK = {"pairs": [
    {  # Cardano / Minswap — ~$1.37M liquidity, matches observed reserves
        "chainId": "cardano", "dexId": "minswap", "pairAddress": "f5808c...",
        "baseToken": {"symbol": "WMTX"}, "quoteToken": {"symbol": "ADA"},
        "priceUsd": "0.0589", "priceNative": "0.0935",  # ADA = $0.63
        "liquidity": {"usd": 1370000, "base": 11630000, "quote": 1087672},
        "volume": {"h24": 264000},
    },
    {  # A smaller Cardano pool that must NOT be selected
        "chainId": "cardano", "dexId": "sundaeswap", "pairAddress": "small",
        "baseToken": {"symbol": "WMTX"}, "quoteToken": {"symbol": "ADA"},
        "priceUsd": "0.0585", "priceNative": "0.0929",
        "liquidity": {"usd": 90000, "base": 770000, "quote": 71000},
        "volume": {"h24": 9000},
    },
    {  # Base / Aerodrome
        "chainId": "base", "dexId": "aerodrome", "pairAddress": "0x3e3...",
        "baseToken": {"symbol": "WMTX"}, "quoteToken": {"symbol": "WETH"},
        "priceUsd": "0.0630", "priceNative": "0.0000180",  # WETH = $3500
        "liquidity": {"usd": 2000000, "base": 15873015, "quote": 285.7},
        "volume": {"h24": 500000},
    },
    {  # Wrong-symbol pair that must be ignored
        "chainId": "base", "dexId": "aerodrome", "pairAddress": "0xjunk",
        "baseToken": {"symbol": "NOTWMTX"}, "quoteToken": {"symbol": "USDC"},
        "priceUsd": "1.0", "priceNative": "1.0",
        "liquidity": {"usd": 999999999, "base": 1, "quote": 1},
    },
]}

fails = 0
def check(name, cond, detail=""):
    global fails
    print(f"{'PASS' if cond else 'FAIL'}: {name} {detail}")
    if not cond:
        fails += 1

# 1. Pool selection
pools = m.select_pools(MOCK["pairs"])
check("both chains found", set(pools) == {"cardano", "base"})
check("deepest cardano pool chosen", pools["cardano"].dex == "minswap")
check("junk pair ignored", pools["base"].dex == "aerodrome")
check("ADA USD price derived", abs(pools["cardano"].quote_price_usd - 0.0589/0.0935) < 1e-9,
      f"= {pools['cardano'].quote_price_usd:.4f}")

# 2. AMM math sanity: buying should cost >= spot (slippage), selling yields <= spot
wmtx, eff_buy = m.buy_wmtx(pools["cardano"], 1000)
check("buy slippage direction", eff_buy > pools["cardano"].price_usd * 0.999,
      f"eff {eff_buy:.5f} vs spot {pools['cardano'].price_usd}")
usd_out, eff_sell = m.sell_wmtx(pools["base"], wmtx)
check("sell slippage direction", eff_sell < pools["base"].price_usd * 1.001,
      f"eff {eff_sell:.5f} vs spot {pools['base'].price_usd}")
# tiny trade should approach spot price closely
_, eff_tiny = m.buy_wmtx(pools["cardano"], 1)
check("tiny trade ~ spot", abs(eff_tiny/pools["cardano"].price_usd - 1) < 0.001,
      f"eff {eff_tiny:.6f}")

# 3. Direction analysis: with a ~7% spot gap, cardano->base should be clearly
#    profitable net of ~0.6% DEX fees + $2.55 fixed + slippage; reverse negative.
a = m.analyse(pools, 1000)
check("spot gap computed", abs(a["spot_gap_pct"] - (0.0630/0.0589 - 1)*100) < 0.01,
      f"= {a['spot_gap_pct']:.2f}%")
check("cheap->rich direction profitable", a["car_to_base"]["net_pct"] > 4,
      f"net = {a['car_to_base']['net_pct']:.2f}%")
check("rich->cheap direction loses", a["base_to_car"]["net_pct"] < 0,
      f"net = {a['base_to_car']['net_pct']:.2f}%")
# conservation sanity: profit_usd consistent with net_pct
c2b = a["car_to_base"]
check("pnl consistency", abs(c2b["profit_usd"] - c2b["net_pct"]/100*1000) < 0.01)

# 4. Full run_once with mocked HTTP + CSV output + alert
csv_path = os.path.join(tempfile.gettempdir(), "test_spreads.csv")
if os.path.exists(csv_path):
    os.remove(csv_path)
resp = MagicMock(); resp.json.return_value = MOCK; resp.raise_for_status.return_value = None
sess = MagicMock(); sess.get.return_value = resp
alert = m.run_once(sess, 1000, 1.5, csv_path)
check("alert fires on big spread", alert is True)
with open(csv_path) as f:
    rows = list(__import__("csv").DictReader(f))
check("csv row written", len(rows) == 1 and rows[0]["alert"] == "True",
      f"net logged: {rows[0]['car_to_base_net_pct']}%")

# 5. Missing-chain handling
alert2 = m.run_once(MagicMock(get=MagicMock(return_value=MagicMock(
    json=MagicMock(return_value={"pairs": MOCK["pairs"][:2]}),
    raise_for_status=MagicMock()))), 1000, 1.5, csv_path)
check("missing chain handled gracefully", alert2 is False)

print(f"\n{'ALL TESTS PASSED' if fails == 0 else f'{fails} FAILURES'}")
raise SystemExit(1 if fails else 0)
