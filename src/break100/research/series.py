"""Bar and tick series with MQL5 `shift` indexing.

MQL5 addresses bars by *shift*: 0 is the still-forming bar, 1 the last closed
bar, and larger values go further back. Porting the detector into Python's
0-is-oldest convention is where off-by-one errors breed, so this module keeps
the MQL5 convention and translates only at the boundary.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class Bar:
    """One OHLC bar. `time` is the bar's opening time, UTC seconds."""

    time: int
    open: float
    high: float
    low: float
    close: float
    tick_volume: int
    spread: int


@dataclass(frozen=True, slots=True)
class Tick:
    """One quote. `time_msc` is UTC milliseconds."""

    time_msc: int
    bid: float
    ask: float


class Series:
    """Chronological bars exposed through MQL5 shift semantics.

    `cursor` marks the index of the currently-forming bar, so `shift=1` is the
    most recently closed bar exactly as `iHigh(_Symbol, tf, 1)` would return it.
    Advancing the cursor replays history bar by bar without look-ahead.
    """

    __slots__ = ("_bars", "_cursor")

    def __init__(self, bars: list[Bar]) -> None:
        self._bars = bars
        self._cursor = len(bars) - 1

    def __len__(self) -> int:
        return len(self._bars)

    @property
    def cursor(self) -> int:
        return self._cursor

    @cursor.setter
    def cursor(self, value: int) -> None:
        if not 0 <= value < len(self._bars):
            raise IndexError(f"cursor {value} outside 0..{len(self._bars) - 1}")
        self._cursor = value

    def bars_available(self) -> int:
        """Mirror of MQL5 `iBars` at the current cursor."""
        return self._cursor + 1

    @property
    def bars(self) -> list[Bar]:
        """Chronological bars, oldest first. Do not mutate."""
        return self._bars

    def at(self, shift: int) -> Bar | None:
        """Bar at `shift`, or None when it falls outside loaded history."""
        idx = self._cursor - shift
        if idx < 0 or idx >= len(self._bars):
            return None
        return self._bars[idx]

    # MQL5 accessors. These return 0.0 for missing bars, as iHigh/iLow/iClose do.
    def high(self, shift: int) -> float:
        bar = self.at(shift)
        return bar.high if bar else 0.0

    def low(self, shift: int) -> float:
        bar = self.at(shift)
        return bar.low if bar else 0.0

    def open(self, shift: int) -> float:
        bar = self.at(shift)
        return bar.open if bar else 0.0

    def close(self, shift: int) -> float:
        bar = self.at(shift)
        return bar.close if bar else 0.0

    def time(self, shift: int) -> int:
        bar = self.at(shift)
        return bar.time if bar else 0


def _to_float(raw: str) -> float:
    try:
        return float(raw)
    except (TypeError, ValueError):
        return 0.0


def _to_int(raw: str) -> int:
    try:
        return int(float(raw))
    except (TypeError, ValueError):
        return 0


def load_bars(paths: list[Path]) -> list[Bar]:
    """Load and merge bar CSVs, de-duplicating on bar time.

    Accepts both schemas in play: `BREAK100_hist_*` from the export script and
    `BREAK100_bars_*` appended live by Capture.mqh. They share a header, but the
    live files can contain repeated rows across terminal restarts, so the last
    row seen for a given timestamp wins.
    """
    merged: dict[int, Bar] = {}
    for path in paths:
        if not path.exists():
            continue
        with path.open(newline="", encoding="utf-8", errors="replace") as fh:
            for row in csv.DictReader(fh):
                time_utc = _to_int(row.get("time_utc", ""))
                if time_utc <= 0:
                    continue
                high = _to_float(row.get("high", ""))
                low = _to_float(row.get("low", ""))
                if high <= 0.0 or low <= 0.0 or high < low:
                    continue
                merged[time_utc] = Bar(
                    time=time_utc,
                    open=_to_float(row.get("open", "")),
                    high=high,
                    low=low,
                    close=_to_float(row.get("close", "")),
                    tick_volume=_to_int(row.get("tick_volume", "")),
                    spread=_to_int(row.get("spread", "")),
                )
    return [merged[t] for t in sorted(merged)]


def load_ticks(paths: list[Path]) -> list[Tick]:
    """Load and merge tick CSVs, sorted by time, dropping crossed quotes."""
    seen: dict[int, Tick] = {}
    for path in paths:
        if not path.exists():
            continue
        with path.open(newline="", encoding="utf-8", errors="replace") as fh:
            for row in csv.DictReader(fh):
                time_msc = _to_int(row.get("utc_ms", ""))
                bid = _to_float(row.get("bid", ""))
                ask = _to_float(row.get("ask", ""))
                if time_msc <= 0 or bid <= 0.0 or ask < bid:
                    continue
                seen[time_msc] = Tick(time_msc=time_msc, bid=bid, ask=ask)
    return [seen[t] for t in sorted(seen)]
