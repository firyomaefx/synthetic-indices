"""Port of the BREAK100 M30 box detector from `mql5/Include/Break100/Box.mqh`.

This is a deliberate line-for-line transcription, not a re-implementation. If
research logic and production logic drift, every backtest result becomes
fiction, so the structure, the clamp order and the loop bounds all mirror the
MQL5 exactly — including behaviour that looks redundant.

`tests/test_box_parity.py` asserts this agrees with the live EA bar for bar.
"""

from __future__ import annotations

from dataclasses import dataclass

from break100.research.series import Series

H4_SECONDS = 4 * 60 * 60


@dataclass(frozen=True, slots=True)
class BoxParams:
    """Mirrors the EA's box inputs. Defaults match "Break100 Box Trading" v2.20."""

    min_bars: int = 4
    max_bars: int = 8
    atr_period: int = 14
    h4_frac: float = 0.25
    widen: float = 0.10
    impulse_k: float = 0.0
    timeout_bars: int = 10
    sl_buf: float = 0.15


@dataclass(frozen=True, slots=True)
class Impulse:
    """The candle immediately preceding the box, when it qualifies."""

    direction: int
    height: float
    vs_box: float
    box_at: float


@dataclass(frozen=True, slots=True)
class RangePattern:
    """Shape descriptors for a detected box — the model's feature inputs."""

    touches_hi: int
    touches_lo: int
    close_loc: float
    compress: float
    h_vs_h4: float


@dataclass(frozen=True, slots=True)
class Cluster:
    """A detected consolidation and the stop rails derived from it."""

    high: float
    low: float
    height: float
    t_left: int
    t_right: int
    bars: int
    atr: float = 0.0
    """Mean true range over `BoxParams.atr_period` bars, from `mean_true_range()`.

    Output only -- nothing in detection or execution branches on this.
    Defaulted so every existing keyword construction of a `Cluster` (fixtures,
    tests) stays valid without naming it.
    """

    def stops(self, point: float) -> tuple[float, float]:
        """Buy-stop and sell-stop, matching the EA's 2%-of-height offset."""
        offset = max(point, 0.02 * max(self.height, point))
        return self.high + offset, self.low - offset


def h4_span_at(h4: Series, now_utc: int) -> float:
    """`B100H4Span()` — range of the last H4 bar *closed* at or before `now_utc`.

    The EA reads `iHigh(_Symbol, PERIOD_H4, 1)`, which is whatever H4 bar has
    most recently closed. Replay must resolve that against the M30 clock or the
    detector silently gains look-ahead.
    """
    for bar in reversed(h4.bars):
        if bar.time + H4_SECONDS <= now_utc:
            return bar.high - bar.low if bar.high > bar.low else 0.0
    return 0.0


def impulse_before(
    series: Series,
    end_shift: int,
    n_bars: int,
    box_h: float,
    impulse_k: float,
) -> Impulse | None:
    """`B100ImpulseBefore()` — the bar just older than the box, if it is a thrust."""
    if box_h <= 0.0 or n_bars < 1:
        return None
    ish = end_shift + n_bars
    ih = series.high(ish)
    il = series.low(ish)
    io = series.open(ish)
    ic = series.close(ish)
    imp_h = ih - il
    if imp_h <= 0.0:
        return None
    body = abs(ic - io)
    k = max(1.2, impulse_k)
    if imp_h < k * box_h:
        return None
    if body < 0.45 * imp_h:
        return None
    return Impulse(
        direction=1 if ic >= io else -1,
        height=imp_h,
        vs_box=imp_h / box_h,
        box_at=(ic - il) / imp_h,
    )


def range_pattern(
    series: Series,
    end_shift: int,
    n_bars: int,
    hi: float,
    lo: float,
    h4_span: float,
) -> RangePattern:
    """`B100RangePattern()` — touch counts and compression over the box."""
    height = hi - lo
    if height <= 0.0:
        return RangePattern(0, 0, 0.5, 1.0, 0.0)

    h_vs_h4 = (height / h4_span) if h4_span > 0.0 else 0.0
    band = 0.10 * height
    touches_hi = 0
    touches_lo = 0
    for i in range(end_shift, end_shift + n_bars):
        if series.high(i) >= hi - band:
            touches_hi += 1
        if series.low(i) <= lo + band:
            touches_lo += 1

    close_loc = (series.close(end_shift) - lo) / height
    compress = 1.0
    if n_bars >= 2:
        h2 = max(series.high(end_shift), series.high(end_shift + 1))
        l2 = min(series.low(end_shift), series.low(end_shift + 1))
        compress = (h2 - l2) / height
    return RangePattern(touches_hi, touches_lo, close_loc, compress, h_vs_h4)


def mean_true_range(series: Series, end_shift: int, period: int) -> float:
    """`B100MeanTrueRange()` — simple (not Wilder) mean true range.

    Output only; nothing in detection or execution branches on this. Returns
    0.0 when there is not enough history for a full window.
    """
    if period <= 0:
        return 0.0
    if series.bars_available() < end_shift + period + 1:
        return 0.0
    total = 0.0
    for i in range(period):
        sh = end_shift + i
        h = series.high(sh)
        low = series.low(sh)
        pc = series.close(sh + 1)
        total += max(h - low, max(abs(h - pc), abs(low - pc)))
    return total / period


def find_cluster_at(
    series: Series,
    end_shift: int,
    params: BoxParams,
    h4_span: float,
) -> Cluster | None:
    """`B100FindClusterAt()` — the box detector.

    `end_shift` is the *newest* bar of the candidate box (the EA scans at 1).
    Rails are wick high/low, never body.
    """
    if end_shift < 1:
        return None
    if params.atr_period < 0:
        return None
    if h4_span <= 0.0:
        return None

    minb = max(4, params.min_bars)
    maxb = max(minb, params.max_bars)
    if series.bars_available() < end_shift + maxb + 2:
        return None

    hi = series.high(end_shift)
    lo = series.low(end_shift)
    n_bars = 1
    for i in range(1, minb):
        h = series.high(end_shift + i)
        low = series.low(end_shift + i)
        if h > hi:
            hi = h
        if low < lo:
            lo = low
        n_bars += 1

    frac = max(0.10, min(params.h4_frac, 0.40))
    poke = max(0.05, min(params.widen, 0.15))
    if hi - lo > frac * h4_span:
        return None

    for sh in range(end_shift + minb, end_shift + maxb):
        h = series.high(sh)
        low = series.low(sh)
        height = hi - lo
        if height <= 0.0:
            break
        room = poke * height
        if h > hi + room or low < lo - room:
            break
        nhi = max(hi, h)
        nlo = min(lo, low)
        if nhi - nlo > frac * h4_span:
            break
        hi = nhi
        lo = nlo
        n_bars += 1

    if n_bars < minb:
        return None

    if params.impulse_k > 0.0 and impulse_before(
        series, end_shift, n_bars, hi - lo, params.impulse_k
    ) is None:
        return None

    return Cluster(
        high=hi,
        low=lo,
        height=hi - lo,
        t_left=series.time(end_shift + n_bars - 1),
        t_right=series.time(end_shift),
        bars=n_bars,
        atr=mean_true_range(series, end_shift, params.atr_period),
    )
