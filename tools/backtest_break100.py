"""Backtest the BREAK100 box straddle over the full available tick history.

    py -3.13 tools/backtest_break100.py

Runs every configuration against both M30 and M15 boxes in one pass. Each
configuration is a trial, and the trial count sets the bar a result must clear:
searching enough variants over one dataset guarantees a winner even when every
variant is worthless.
"""

from __future__ import annotations

import csv
import glob
import sys
from array import array
from pathlib import Path

sys.path.insert(0, "src")

from break100.research.backtest import (  # noqa: E402
    HEADER,
    Config,
    Costs,
    Report,
    TickBook,
    noise_threshold,
    run,
)
from break100.research.boxdetect import BoxParams  # noqa: E402
from break100.research.replay import BoxEvent, replay  # noqa: E402
from break100.research.series import Series, load_bars  # noqa: E402

COMMON = Path(r"C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files")
SPREAD = 5.00


def load_ticks(symbol: str = "BREAK100") -> TickBook:
    """Load every exported tick file into compact arrays."""
    times: array[int] = array("q")
    bids: array[float] = array("d")
    asks: array[float] = array("d")
    files = sorted(glob.glob(str(COMMON / f"BREAK100_histticks_{symbol}_*.csv")))
    for path in files:
        with open(path, newline="", encoding="utf-8", errors="replace") as fh:
            for row in csv.DictReader(fh):
                try:
                    t, b, a = int(row["utc_ms"]), float(row["bid"]), float(row["ask"])
                except (KeyError, TypeError, ValueError):
                    continue
                if t > 0 and b > 0 and a >= b:
                    times.append(t)
                    bids.append(b)
                    asks.append(a)
    print(f"loaded {len(times):,} ticks from {len(files)} files")
    return TickBook(times, bids, asks)


def load_events(tf: str, ref: str) -> tuple[list[BoxEvent], int]:
    box = Series(load_bars([COMMON / f"BREAK100_hist_BREAK100_{tf}.csv"]))
    reference = Series(load_bars([COMMON / f"BREAK100_hist_BREAK100_{ref}.csv"]))
    events = replay(box, reference, BoxParams(), point=0.01)
    print(f"  {tf} boxes / {ref} ref: {len(box)} bars -> {len(events)} armed boxes")
    return events, {"M15": 900, "M30": 1800}[tf]


def variants(bar_seconds: int) -> list[tuple[str, Config]]:
    base = {"bar_seconds": bar_seconds, "risk_fraction": 0.0025}
    return [
        ("baseline (as shipped)", Config(tp1_r=1.0, **base)),
        ("TP1 covers costs", Config(tp1_r=1.0, tp1_covers_costs=True, **base)),
        ("TP1 = 2R", Config(tp1_r=2.0, **base)),
        ("TP1 2R + costs", Config(tp1_r=2.0, tp1_covers_costs=True, **base)),
        ("breakeven @1R", Config(tp1_r=2.0, breakeven_at_r=1.0, **base)),
        ("trail from 1R", Config(tp1_r=3.0, trail_start_r=1.0, trail_distance_r=0.5, **base)),
        ("trail tight 0.25R", Config(tp1_r=3.0, trail_start_r=0.5, trail_distance_r=0.25, **base)),
        ("cooldown 4 bars", Config(tp1_r=2.0, cooldown_bars=4, **base)),
        (
            "trail + cooldown",
            Config(tp1_r=3.0, trail_start_r=1.0, trail_distance_r=0.5, cooldown_bars=4, **base),
        ),
        (
            "everything on",
            Config(
                tp1_r=3.0, trail_start_r=1.0, trail_distance_r=0.5, breakeven_at_r=1.0,
                cooldown_bars=4, tp1_covers_costs=True, **base,
            ),
        ),
    ]


def main() -> int:
    print("BREAK100 box straddle — full tick backtest\n")
    book = load_ticks()
    if len(book) == 0:
        print("no ticks — run tools/export_history.py first")
        return 1

    all_reports: list[Report] = []
    for tf, ref in (("M30", "H4"), ("M15", "H1")):
        events, bar_seconds = load_events(tf, ref)
        if not events:
            continue
        print(f"\n{tf} boxes / {ref} reference   spread {SPREAD:.2f}   risk 0.25%/trade\n")
        print(HEADER)
        print("-" * len(HEADER))
        for label, cfg in variants(bar_seconds):
            rep = run(f"{tf} {label}", events, book, cfg, Costs(), SPREAD)
            all_reports.append(rep)
            print(rep.line())
        print()

    if not all_reports:
        return 1

    trials = len(all_reports)
    bar = noise_threshold(trials)
    best = max(all_reports, key=lambda r: r.expectancy_t)
    print("=" * len(HEADER))
    print(f"best by t-stat: {best.label}")
    print(
        f"   ROI {best.roi * 100:+.2f}% over {best.days:.0f} days | {best.trades} trades | "
        f"Sharpe {best.sharpe:.2f} | MaxDD {best.max_drawdown * 100:.2f}%"
    )
    print(f"   expectancy {best.expectancy_r:+.3f}R  (t = {best.expectancy_t:+.2f})")
    print(f"   exits: {best.exits}")
    print()
    print(f"Multiple-testing bar: {trials} configurations were tried. If every one of")
    print("them had exactly zero edge, the luckiest would still typically reach")
    print(f"t = {bar:.2f}. A result only means something above that line.")
    verdict = "CLEARS" if best.expectancy_t > bar else "does NOT clear"
    print(f"   best observed t = {best.expectancy_t:+.2f}  ->  {verdict} the bar")
    profitable = [r for r in all_reports if r.roi > 0]
    print(f"\n{len(profitable)} of {trials} configurations were profitable at all.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
