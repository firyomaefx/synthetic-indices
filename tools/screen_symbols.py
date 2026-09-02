"""Run the structure battery against live MT5 symbols.

Read-only: `copy_ticks_range`, `copy_rates_from_pos`, `symbol_info`. No order
function is called.

    py -3.13 tools/screen_symbols.py --symbols TICK1,TICK3,UP500,DOWN500,BREAK100,VOL20
    py -3.13 tools/screen_symbols.py --group "Synthetic Indices" --days 7
"""

from __future__ import annotations

import argparse
import statistics as st
import sys
from datetime import UTC, datetime, timedelta
from typing import Any

sys.path.insert(0, "src")

from break100.research.structure import StructureReport, classify  # noqa: E402


def load_steps(mt5: Any, symbol: str, days: int, use_bars: bool = False) -> list[float]:
    """Bid-to-bid steps over the last `days`, falling back to M1 closes.

    `use_bars` skips the tick pull entirely. Across a 140-symbol sweep the tick
    route is the whole runtime, and M1 is the right granularity anyway for a
    strategy that trades M30 boxes.
    """
    bids: list[float] = []
    if not use_bars:
        to = datetime.now(UTC)
        frm = to - timedelta(days=days)
        ticks = mt5.copy_ticks_range(symbol, frm, to, mt5.COPY_TICKS_ALL)
        if ticks is not None and len(ticks) > 1000:
            bids = [float(t["bid"]) for t in ticks]
    if not bids:
        rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M1, 0, 99_999)
        if rates is None or len(rates) < 1001:
            return []
        bids = [float(r["close"]) for r in rates]
    return [b - a for a, b in zip(bids, bids[1:], strict=False)]


def median_daily_range(mt5: Any, symbol: str) -> float:
    rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_D1, 0, 99_999)
    if rates is None or len(rates) == 0:
        return 0.0
    return st.median([float(r["high"]) - float(r["low"]) for r in rates])


def screen(
    mt5: Any, symbol: str, days: int, use_bars: bool = False
) -> StructureReport | None:
    if not mt5.symbol_select(symbol, True):
        return None
    info = mt5.symbol_info(symbol)
    steps = load_steps(mt5, symbol, days, use_bars)
    if not steps:
        return None
    return classify(
        symbol=symbol,
        steps=steps,
        spread=info.spread * info.point,
        median_daily_range=median_daily_range(mt5, symbol),
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--symbols", default="")
    ap.add_argument("--group", default="")
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--bars", action="store_true", help="Use M1 bars, skip ticks (fast)")
    args = ap.parse_args()

    try:
        import MetaTrader5 as mt5  # noqa: N813
    except ImportError:
        print("pip install MetaTrader5")
        return 2
    if not mt5.initialize():
        print(f"MT5 initialize failed: {mt5.last_error()}")
        return 1
    try:
        if args.symbols:
            names = [s.strip() for s in args.symbols.split(",") if s.strip()]
        elif args.group:
            names = [s.name for s in mt5.symbols_get() if s.path.startswith(args.group)]
        else:
            names = [s.name for s in mt5.symbols_get()]

        head = (
            f"{'symbol':<14}{'verdict':<22}{'skew':>8}{'skew_z':>9}"
            f"{'kurt':>8}{'drift_t':>9}{'VR60':>7}{'cost%':>8}  description"
        )
        print(head)
        print("-" * len(head))
        results: list[StructureReport] = []
        for name in names:
            rep = screen(mt5, name, args.days, args.bars)
            if rep is None:
                print(f"{name:<14}{'NO DATA':<22}")
                continue
            results.append(rep)
            info = mt5.symbol_info(name)
            m = rep.moments
            print(
                f"{rep.symbol:<14}{rep.verdict.value:<22}{m.skew:>8.3f}{m.skew_z:>9.1f}"
                f"{m.kurtosis:>8.1f}{m.drift_t:>9.2f}"
                f"{rep.variance_ratio.get(60, 1.0):>7.3f}{rep.cost_hurdle * 100:>7.2f}%"
                f"  {info.description[:38]}"
            )
            for note in rep.notes:
                print(f"{'':<14}  - {note}")

        tradeable = [r for r in results if r.tradeable]
        print(f"\n{len(tradeable)} of {len(results)} show structure worth a second look")
        for r in sorted(tradeable, key=lambda r: r.cost_hurdle):
            print(f"   {r.symbol:<14}{r.verdict.value:<22}cost {r.cost_hurdle * 100:.2f}%")
    finally:
        mt5.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
