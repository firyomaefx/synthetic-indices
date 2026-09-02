"""Export maximum available BREAK100 history from a running MT5 terminal.

Read-only: this calls only `copy_rates_*` and `copy_ticks_*`. It never touches
an order function.

Writes into MT5's Common\\Files using the same schema as
`mql5/Scripts/Break100 Box Trading History Export.mq5`, under a `hist_` prefix
so it can never truncate the `BREAK100_bars_*` / `BREAK100_ticks_*` files that
Capture.mqh appends to while the EA runs.

Requires the `MetaTrader5` package and a running terminal:

    py -3.13 tools/export_history.py --symbol BREAK100
"""

from __future__ import annotations

import argparse
import csv
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

# copy_rates_from_pos rejects a count of 100_000 outright; 99_999 is the real cap.
MAX_BARS = 99_999

BAR_HEADER = [
    "time_utc", "time_gmt", "open", "high", "low", "close",
    "tick_volume", "spread", "real_volume",
]
TICK_HEADER = ["utc_ms", "bid", "ask", "last", "volume", "flags"]


def _timeframes(mt5: Any) -> list[tuple[str, int]]:
    return [
        ("M1", mt5.TIMEFRAME_M1),
        ("M5", mt5.TIMEFRAME_M5),
        ("M15", mt5.TIMEFRAME_M15),
        ("M30", mt5.TIMEFRAME_M30),
        ("H1", mt5.TIMEFRAME_H1),
        ("H4", mt5.TIMEFRAME_H4),
        ("D1", mt5.TIMEFRAME_D1),
    ]


def export_bars(mt5: Any, symbol: str, out_dir: Path, digits: int) -> dict[str, int]:
    counts: dict[str, int] = {}
    for name, tf in _timeframes(mt5):
        rates = mt5.copy_rates_from_pos(symbol, tf, 0, MAX_BARS)
        if rates is None or len(rates) == 0:
            print(f"  {name:<4} none ({mt5.last_error()})")
            counts[name] = 0
            continue
        path = out_dir / f"BREAK100_hist_{symbol.replace(' ', '_')}_{name}.csv"
        with path.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(BAR_HEADER)
            for r in rates:
                t = int(r["time"])
                writer.writerow([
                    t,
                    datetime.fromtimestamp(t, UTC).strftime("%Y.%m.%d %H:%M:%S"),
                    f"{float(r['open']):.{digits}f}",
                    f"{float(r['high']):.{digits}f}",
                    f"{float(r['low']):.{digits}f}",
                    f"{float(r['close']):.{digits}f}",
                    int(r["tick_volume"]),
                    int(r["spread"]),
                    int(r["real_volume"]),
                ])
        counts[name] = len(rates)
        first = datetime.fromtimestamp(int(rates[0]["time"]), UTC)
        last = datetime.fromtimestamp(int(rates[-1]["time"]), UTC)
        print(
            f"  {name:<4} {len(rates):>6} bars  {first:%Y-%m-%d} .. {last:%Y-%m-%d}"
            f"  -> {path.name}"
        )
    return counts


def export_ticks(mt5: Any, symbol: str, out_dir: Path, days: int, digits: int) -> int:
    total = 0
    today = datetime.now(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
    for back in range(days, -1, -1):
        day0 = today - timedelta(days=back)
        ticks = mt5.copy_ticks_range(symbol, day0, day0 + timedelta(days=1), mt5.COPY_TICKS_ALL)
        if ticks is None or len(ticks) == 0:
            continue
        path = out_dir / f"BREAK100_histticks_{symbol.replace(' ', '_')}_{day0:%Y%m%d}.csv"
        with path.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(TICK_HEADER)
            for t in ticks:
                writer.writerow([
                    int(t["time_msc"]),
                    f"{float(t['bid']):.{digits}f}",
                    f"{float(t['ask']):.{digits}f}",
                    f"{float(t['last']):.{digits}f}",
                    int(t["volume"]),
                    int(t["flags"]),
                ])
        total += len(ticks)
        print(f"  {day0:%Y-%m-%d}  {len(ticks):>7} ticks")
    return total


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--symbol", default="BREAK100")
    parser.add_argument("--tick-days", type=int, default=60)
    parser.add_argument("--no-ticks", action="store_true")
    parser.add_argument("--out", default="", help="Output dir (default: MT5 Common\\Files)")
    args = parser.parse_args()

    try:
        import MetaTrader5 as mt5  # noqa: N813
    except ImportError:
        print("MetaTrader5 package not installed: py -3.13 -m pip install MetaTrader5")
        return 2

    if not mt5.initialize():
        print(f"MT5 initialize failed: {mt5.last_error()}  (is the terminal running?)")
        return 1
    try:
        if not mt5.symbol_select(args.symbol, True):
            print(f"symbol_select({args.symbol}) failed: {mt5.last_error()}")
            return 1
        info = mt5.symbol_info(args.symbol)
        terminal = mt5.terminal_info()
        out_dir = Path(args.out) if args.out else Path(terminal.commondata_path) / "Files"
        out_dir.mkdir(parents=True, exist_ok=True)

        print(f"symbol {args.symbol}  digits={info.digits} point={info.point}")
        print(f"output {out_dir}\n")
        export_bars(mt5, args.symbol, out_dir, info.digits)
        if not args.no_ticks:
            print("\nticks:")
            n = export_ticks(mt5, args.symbol, out_dir, args.tick_days, info.digits)
            print(f"  total {n} ticks")
    finally:
        mt5.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
