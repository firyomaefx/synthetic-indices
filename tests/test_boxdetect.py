"""Behavioural pins for the Box.mqh port.

These encode the MQL5 semantics that are easy to break in translation: the
clamp order, the extension loop bounds, and the fact that H4 span must resolve
to the last *closed* H4 bar rather than the one in progress.
"""

from __future__ import annotations

from break100.research.boxdetect import (
    BoxParams,
    find_cluster_at,
    h4_span_at,
    impulse_before,
    mean_true_range,
    range_pattern,
)
from break100.research.series import Bar, Series

M30 = 30 * 60
H4 = 4 * 60 * 60


def make_series(specs: list[tuple[float, float, float, float]], step: int = M30) -> Series:
    """Build a Series from (open, high, low, close) tuples, oldest first."""
    bars = [
        Bar(
            time=1_787_000_000 + i * step,
            open=o,
            high=h,
            low=lo,
            close=c,
            tick_volume=100,
            spread=500,
        )
        for i, (o, h, lo, c) in enumerate(specs)
    ]
    return Series(bars)


def flat(n: int, high: float = 100.0, low: float = 90.0) -> list[tuple[float, float, float, float]]:
    return [(95.0, high, low, 95.0)] * n


def test_uniform_box_extends_to_max_bars() -> None:
    # Every bar overlaps perfectly, so the extension loop should run to maxb.
    series = make_series(flat(20))
    cluster = find_cluster_at(series, 1, BoxParams(), h4_span=100.0)
    assert cluster is not None
    assert cluster.bars == 8  # maxb
    assert cluster.high == 100.0
    assert cluster.low == 90.0
    assert cluster.height == 10.0


def test_box_taller_than_h4_fraction_is_rejected() -> None:
    # height 10 vs frac 0.25 * span 20 = 5.0 ceiling.
    series = make_series(flat(20))
    assert find_cluster_at(series, 1, BoxParams(), h4_span=20.0) is None


def test_h4_fraction_is_clamped_to_the_mql5_range() -> None:
    # h4_frac is clamped into [0.10, 0.40]; 5.0 must behave exactly like 0.40.
    series = make_series(flat(20))
    wide = find_cluster_at(series, 1, BoxParams(h4_frac=5.0), h4_span=100.0)
    at_ceiling = find_cluster_at(series, 1, BoxParams(h4_frac=0.40), h4_span=100.0)
    assert wide == at_ceiling


def test_extension_stops_at_a_bar_that_pokes_past_the_widen_room() -> None:
    # room = 0.10 * 10 = 1.0, so a high of 102 at shift 5 breaks the loop.
    specs = flat(20)
    specs[-6] = (95.0, 102.0, 90.0, 95.0)  # shift 5 when cursor is the last bar
    series = make_series(specs)
    cluster = find_cluster_at(series, 1, BoxParams(), h4_span=100.0)
    assert cluster is not None
    assert cluster.bars == 4  # minb only; extension stopped immediately


def test_insufficient_history_is_rejected() -> None:
    # Needs end_shift + maxb + 2 = 11 bars available.
    assert find_cluster_at(make_series(flat(10)), 1, BoxParams(), h4_span=100.0) is None
    assert find_cluster_at(make_series(flat(11)), 1, BoxParams(), h4_span=100.0) is not None


# --- mean true range (previously dead: Box.mqh set atr=0.0 and never touched it again) --


def test_mean_true_range_matches_the_hand_computed_value() -> None:
    # Every bar: high=100, low=90, prior close=95. TR = max(10, |100-95|, |90-95|) = 10.
    series = make_series(flat(20))
    assert mean_true_range(series, end_shift=1, period=14) == 10.0


def test_mean_true_range_is_zero_without_a_full_window() -> None:
    # bars_available() must be >= end_shift + period + 1; 16 bars is one short of 17.
    assert mean_true_range(make_series(flat(16)), end_shift=1, period=15) == 0.0
    assert mean_true_range(make_series(flat(17)), end_shift=1, period=15) == 10.0


def test_mean_true_range_is_zero_for_a_non_positive_period() -> None:
    series = make_series(flat(20))
    assert mean_true_range(series, end_shift=1, period=0) == 0.0


def test_reviving_atr_does_not_move_any_rail() -> None:
    # atr is an output only. The cluster's rails and bar count must be identical
    # to a cluster built before atr existed -- only the new field should differ.
    series = make_series(flat(20))
    cluster = find_cluster_at(series, 1, BoxParams(), h4_span=100.0)
    assert cluster is not None
    assert cluster.high == 100.0
    assert cluster.low == 90.0
    assert cluster.bars == 8
    assert cluster.atr == 10.0


def test_atr_is_zero_when_history_is_too_short_for_a_full_window() -> None:
    # 11 bars clears the detector's own end_shift+maxb+2=11 floor but is short
    # of end_shift+atr_period+1=16, so the box still forms and atr stays 0.0.
    series = make_series(flat(11))
    cluster = find_cluster_at(series, 1, BoxParams(), h4_span=100.0)
    assert cluster is not None
    assert cluster.atr == 0.0


def test_zero_h4_span_is_rejected() -> None:
    assert find_cluster_at(make_series(flat(20)), 1, BoxParams(), h4_span=0.0) is None


def test_impulse_gate_rejects_when_no_thrust_precedes_the_box() -> None:
    # Uniform bars: the preceding candle is the same size as the box, so a
    # required impulse of 1.5x cannot be satisfied.
    series = make_series(flat(20))
    assert find_cluster_at(series, 1, BoxParams(impulse_k=1.5), h4_span=100.0) is None


def test_impulse_detected_when_prior_bar_is_a_large_bodied_thrust() -> None:
    series = make_series(flat(20))
    # Box of 4 bars at shift 1..4 means the impulse candle sits at shift 5.
    specs = flat(20)
    specs[-6] = (70.0, 130.0, 68.0, 128.0)  # tall, body >= 45% of range
    series = make_series(specs)
    imp = impulse_before(series, 1, 4, box_h=10.0, impulse_k=1.5)
    assert imp is not None
    assert imp.direction == 1
    assert imp.height == 62.0


def test_stops_sit_two_percent_of_height_outside_the_rails() -> None:
    series = make_series(flat(20))
    cluster = find_cluster_at(series, 1, BoxParams(), h4_span=100.0)
    assert cluster is not None
    buy, sell = cluster.stops(point=0.01)
    assert buy == 100.0 + 0.2
    assert sell == 90.0 - 0.2


def test_range_pattern_counts_touches_within_a_ten_percent_band() -> None:
    series = make_series(flat(20))
    pattern = range_pattern(series, 1, 4, hi=100.0, lo=90.0, h4_span=100.0)
    assert pattern.touches_hi == 4
    assert pattern.touches_lo == 4
    assert pattern.h_vs_h4 == 0.1
    assert pattern.compress == 1.0


def test_h4_span_uses_the_last_closed_bar_not_the_forming_one() -> None:
    t0 = 1_787_000_000
    h4 = Series(
        [
            Bar(time=t0, open=1.0, high=50.0, low=40.0, close=45.0, tick_volume=1, spread=1),
            Bar(time=t0 + H4, open=1.0, high=80.0, low=20.0, close=45.0, tick_volume=1, spread=1),
        ]
    )
    # One second before the second bar closes, only the first has closed.
    assert h4_span_at(h4, t0 + 2 * H4 - 1) == 10.0
    # At its close, the second bar becomes available.
    assert h4_span_at(h4, t0 + 2 * H4) == 60.0
    # Before any bar has closed there is no span, which the detector rejects on.
    assert h4_span_at(h4, t0) == 0.0
