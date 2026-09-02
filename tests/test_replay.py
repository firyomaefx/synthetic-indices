"""Pins for the arm/fill/timeout state machine in replay.py."""

from __future__ import annotations

from break100.research.boxdetect import BoxParams
from break100.research.replay import Outcome, replay
from break100.research.series import Bar, Series

M30 = 30 * 60
H4 = 4 * 60 * 60
T0 = 1_787_000_000


def series_from(specs: list[tuple[float, float]], step: int = M30) -> Series:
    """Build a Series from (high, low) pairs; open/close sit mid-range."""
    bars = []
    for i, (hi, lo) in enumerate(specs):
        mid = (hi + lo) / 2.0
        bars.append(
            Bar(time=T0 + i * step, open=mid, high=hi, low=lo, close=mid,
                tick_volume=100, spread=500)
        )
    return Series(bars)


def h4_series() -> Series:
    """H4 bars wide enough that the 0.25 fraction never binds."""
    return Series(
        [
            Bar(time=T0 - 4 * H4 + i * H4, open=95.0, high=150.0, low=50.0, close=95.0,
                tick_volume=1, spread=1)
            for i in range(40)
        ]
    )


def test_single_rail_touch_labels_a_directional_breakout() -> None:
    # A trailing bar is required: shift 1 is the last *closed* bar, so the final
    # bar of a series is still "forming" and is never evaluated.
    specs = [(100.0, 90.0)] * 14 + [(140.0, 95.0)] + [(100.0, 90.0)]
    events = replay(series_from(specs), h4_series(), BoxParams(), point=0.01)
    assert len(events) == 1
    assert events[0].outcome is Outcome.BREAKOUT_UP


def test_both_rails_in_one_bar_is_ambiguous_not_a_guess() -> None:
    specs = [(100.0, 90.0)] * 14 + [(140.0, 50.0)] + [(100.0, 90.0)]
    events = replay(series_from(specs), h4_series(), BoxParams(), point=0.01)
    assert len(events) == 1
    assert events[0].outcome is Outcome.AMBIGUOUS


def test_quiet_market_times_the_box_out() -> None:
    # 14 bars to arm, then nothing but inside bars for the full timeout.
    specs = [(100.0, 90.0)] * 30
    events = replay(series_from(specs), h4_series(), BoxParams(timeout_bars=10), point=0.01)
    assert events
    assert events[0].outcome is Outcome.TIMEOUT
    assert events[0].bars_waited == 10


def test_lock_bar_prevents_rearming_on_the_resolution_bar() -> None:
    # After a resolution the EA refuses to re-arm on a bar at or before lock_bar.
    specs = [(100.0, 90.0)] * 14 + [(140.0, 95.0)] + [(100.0, 90.0)] * 14
    events = replay(series_from(specs), h4_series(), BoxParams(), point=0.01)
    armed_bars = [e.armed_bar for e in events]
    assert len(armed_bars) == len(set(armed_bars)), "a bar armed twice"
    for earlier, later in zip(events, events[1:], strict=False):
        assert later.armed_bar > earlier.resolved_bar or earlier.resolved_bar == 0


def test_unresolved_box_at_end_of_history_is_reported_not_dropped() -> None:
    # Arms near the end with too few bars left to time out.
    specs = [(100.0, 90.0)] * 16
    events = replay(series_from(specs), h4_series(), BoxParams(timeout_bars=10), point=0.01)
    assert events
    assert events[-1].outcome is Outcome.UNRESOLVED


def test_features_are_captured_at_arm_time() -> None:
    specs = [(100.0, 90.0)] * 14 + [(140.0, 95.0)]
    events = replay(series_from(specs), h4_series(), BoxParams(), point=0.01)
    f = events[0].features
    assert f.touches_hi > 0
    assert f.touches_lo > 0
    assert f.spread_pts == 500
    assert f.phase in {"IMPULSE_THEN_RANGE", "RANGE_THEN_BREAK"}
    assert 0 <= f.hour_utc <= 23
    assert 0 <= f.dow <= 6
