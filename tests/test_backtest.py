"""Pins for the tick engine and the payoff-asymmetry battery.

`backtest.py` is the only tick-aware code in the repo and had no tests at all, so
these start by fixing the fill and path arithmetic before asserting anything about
asymmetry. Every fixture is a hand-built 1 Hz quote stream with the expected values
worked out in the comment, in the style of `test_boxdetect.py`.
"""

from __future__ import annotations

from break100.research.backtest import (
    Asymmetry,
    Config,
    Costs,
    Exit,
    TickBook,
    Trade,
    _simulate_one,
    asymmetry,
)
from break100.research.boxdetect import Cluster
from break100.research.replay import BoxEvent, BoxFeatures, Outcome

# The box: 900..1000, height 100. With sl_buf = 0 the stop distance is exactly
# 100, so every R figure below is "price move / 100" and can be read by eye.
HEIGHT = 100.0
BUY_STOP = 1010.0
SELL_STOP = 890.0
ARMED_BAR = 0
FIRST_TICK = 1800  # cfg.bar_seconds; the entry scan may not start before this
SPREAD = 2.0

CFG = Config(sl_buf=0.0, tp1_r=1.0)
COSTS = Costs()


def book_from_mids(mids: list[float], start: int = FIRST_TICK) -> TickBook:
    """One tick per second at `start`, `start+1`, ... with a fixed 2.00 spread."""
    times = [(start + i) * 1000 for i in range(len(mids))]
    bids = [m - SPREAD / 2 for m in mids]
    asks = [m + SPREAD / 2 for m in mids]
    return TickBook(times, bids, asks)


def event() -> BoxEvent:
    features = BoxFeatures(
        touches_hi=0, touches_lo=0, close_loc=0.5, compress=0.0, h_vs_h4=0.0,
        imp_dir=0, imp_vs_box=0.0, box_at=0.5, phase="RANGE_THEN_BREAK",
        hour_utc=0, dow=1, spread_pts=int(SPREAD),
    )
    return BoxEvent(
        armed_bar=ARMED_BAR,
        cluster=Cluster(high=1000.0, low=900.0, height=HEIGHT, t_left=0, t_right=0, bars=4),
        buy_stop=BUY_STOP,
        sell_stop=SELL_STOP,
        features=features,
        outcome=Outcome.BREAKOUT_UP,
        resolved_bar=ARMED_BAR + 1800,
        bars_waited=1,
    )


def simulate(mids: list[float]) -> Trade:
    trade = _simulate_one(book_from_mids(mids), event(), CFG, COSTS, 10_000.0, SPREAD)
    assert trade is not None, "fixture was expected to fill"
    return trade


# --- fills and slippage -----------------------------------------------------


def test_long_fills_at_the_ask_and_records_what_it_paid_away() -> None:
    # mid 1010 puts the ask at 1011, one full unit through the 1010 stop.
    # Entry is 1011, so slippage is 1.0 price units = 0.01 R against a 100 stop.
    trade = simulate([1000, 1010, 1120])
    assert trade.direction == 1
    assert trade.entry == 1011.0
    assert round(trade.entry_slippage_r, 10) == 0.01


def test_a_gapped_fill_costs_proportionally_more_slippage() -> None:
    # Same box, but the first tick through the level is mid 1060 -> ask 1061.
    # 51 units past the 1010 stop is 0.51 R gone before the trade even starts.
    # This is the term BACKTEST_RESULTS.md flags as unmeasured.
    trade = simulate([1000, 1060, 1200])
    assert trade.entry == 1061.0
    assert round(trade.entry_slippage_r, 10) == 0.51


def test_short_slippage_is_measured_from_the_sell_stop() -> None:
    # mid 880 puts the bid at 879, eleven units below the 890 sell stop.
    trade = simulate([1000, 880, 700])
    assert trade.direction == -1
    assert trade.entry == 879.0
    assert round(trade.entry_slippage_r, 10) == 0.11


# --- the tick path ----------------------------------------------------------


def test_excursions_and_their_timing_are_recorded_separately() -> None:
    # Fill at 1011 on tick 1 (t=1801). Marks are on the bid for a long.
    #   t=1802 mid 1050 -> bid 1049, +38  -> MFE so far
    #   t=1803 mid 1030 -> bid 1029, +18
    #   t=1804 mid  990 -> bid  989, -22  -> MAE, at t+3
    #   t=1805 mid 1120 -> bid 1119, +108 -> through the 1111 target, exits TP
    trade = simulate([1000, 1010, 1050, 1030, 990, 1120])

    assert trade.reason is Exit.TP
    assert round(trade.r_multiple, 10) == 1.08
    assert round(trade.mfe_r, 10) == 1.08
    assert round(trade.mae_r, 10) == -0.22
    assert trade.seconds_to_mfe == 4
    assert trade.seconds_to_mae == 3


def test_extremes_are_unchanged_by_the_order_they_are_reached_in() -> None:
    # The same two extremes, reached in the opposite order. The magnitudes must
    # not depend on the ordering; only the timings do.
    adverse_first = simulate([1000, 1010, 990, 1050, 900])
    favourable_first = simulate([1000, 1010, 1050, 990, 900])

    assert round(adverse_first.mfe_r, 10) == round(favourable_first.mfe_r, 10) == 0.38
    # Fill is at t+0; the dip is at t+1 and the peak at t+2 when adverse leads,
    # and the peak at t+1 when favourable leads.
    assert adverse_first.seconds_to_mfe == 2
    assert favourable_first.seconds_to_mfe == 1


def test_a_loser_still_records_the_profit_it_gave_back() -> None:
    # Fill 1011, runs to bid 1049 (+0.38R), then stops out at 911.
    # r_multiple is a full loss, but 0.38R was on the table first -- the number
    # that says whether the exit rule threw a winner away.
    trade = simulate([1000, 1010, 1050, 900])
    assert trade.reason is Exit.SL
    assert round(trade.mfe_r, 10) == 0.38
    assert trade.r_multiple < 0.0


def test_mae_is_never_positive_and_mfe_is_never_negative() -> None:
    # A trade that goes straight to the stop never trades in front of entry.
    trade = simulate([1000, 1010, 900])
    assert trade.mfe_r == 0.0
    assert trade.mae_r < 0.0


def test_exit_is_bracketed_by_the_excursions_it_walked_through() -> None:
    # The exit fills at one of the marks, so it can be no better than the best
    # and no worse than the worst. This invariant is what makes `capture` <= 1.
    for mids in (
        [1000, 1010, 1050, 990, 1120],
        [1000, 1010, 900],
        [1000, 1010, 1050, 990, 900],
    ):
        trade = simulate(mids)
        assert trade.mae_r <= trade.r_multiple <= trade.mfe_r


# --- the asymmetry battery --------------------------------------------------


def make_trade(r: float, mfe: float, mae: float, t_mfe: int = 30, t_mae: int = 90) -> Trade:
    return Trade(
        entry_time=0, exit_time=60, direction=1, entry=1000.0, stop=900.0,
        target=1100.0, exit_price=1000.0 + r * 100.0, lots=0.01,
        r_multiple=r, pnl=r, reason=Exit.TP if r > 0 else Exit.SL,
        mfe_r=mfe, mae_r=mae, seconds_to_mfe=t_mfe, seconds_to_mae=t_mae,
    )


def test_a_symmetric_path_reports_an_edge_ratio_of_one() -> None:
    # Price travels exactly as far against as it does in favour. No exit rule
    # can manufacture an edge from this, and the number says so.
    trades = [make_trade(r=0.5, mfe=1.0, mae=-1.0) for _ in range(10)]
    assert asymmetry(trades).edge_ratio == 1.0


def test_edge_ratio_exceeds_one_only_when_the_path_actually_favours_the_trade() -> None:
    favourable = asymmetry([make_trade(r=0.5, mfe=2.0, mae=-0.5) for _ in range(10)])
    adverse = asymmetry([make_trade(r=0.5, mfe=0.5, mae=-2.0) for _ in range(10)])
    assert favourable.edge_ratio == 4.0
    assert adverse.edge_ratio == 0.25


def test_capture_separates_a_dead_instrument_from_badly_tuned_exits() -> None:
    # Identical MFE on offer; one set of exits takes a fifth of it, the other most.
    leaky = asymmetry([make_trade(r=0.2, mfe=2.0, mae=-0.5) for _ in range(10)])
    tight = asymmetry([make_trade(r=1.8, mfe=2.0, mae=-0.5) for _ in range(10)])
    assert round(leaky.capture, 10) == 0.1
    assert round(tight.capture, 10) == 0.9
    # Same path, so the exit-independent measure does not move between them.
    assert leaky.edge_ratio == tight.edge_ratio


def test_payoff_and_tail_ratios_read_the_r_distribution() -> None:
    # 5 losers at -1R, 5 winners at +3R.
    trades = [make_trade(r=-1.0, mfe=0.1, mae=-1.0) for _ in range(5)]
    trades += [make_trade(r=3.0, mfe=3.2, mae=-0.2) for _ in range(5)]
    stats = asymmetry(trades)
    assert stats.payoff_ratio == 3.0
    assert stats.tail_ratio == 3.0


def test_time_to_each_extreme_is_reported() -> None:
    # Winners that work in 30s and losers that bleed for 90s are a different
    # instrument from the reverse, even at identical R.
    stats = asymmetry([make_trade(r=1.0, mfe=1.0, mae=-0.2, t_mfe=30, t_mae=90)] * 5)
    assert stats.median_seconds_to_mfe == 30.0
    assert stats.median_seconds_to_mae == 90.0


def test_winner_and_loser_excursions_are_reported_apart() -> None:
    trades = [make_trade(r=-1.0, mfe=0.8, mae=-1.0) for _ in range(4)]
    trades += [make_trade(r=2.0, mfe=2.0, mae=-0.1) for _ in range(4)]
    stats = asymmetry(trades)
    assert round(stats.mae_when_win, 10) == -0.1
    assert round(stats.mae_when_loss, 10) == -1.0
    # Losers had 0.8R on the table before they turned over.
    assert round(stats.mfe_when_loss, 10) == 0.8


def test_asymmetry_of_nothing_is_flat_rather_than_an_error() -> None:
    stats = asymmetry([])
    assert stats == Asymmetry(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)


def test_ratios_stay_finite_when_their_denominator_cannot_be_formed() -> None:
    # All winners: there is no average loss to divide by, and no negative tail.
    stats = asymmetry([make_trade(r=1.0, mfe=1.0, mae=0.0) for _ in range(5)])
    assert stats.payoff_ratio == 0.0
    assert stats.tail_ratio == 0.0
    assert stats.edge_ratio == 0.0
