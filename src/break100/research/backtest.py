"""Tick-level backtest of the box straddle, reporting ROI, Sharpe, MaxDD, trades.

Fills are resolved against the actual bid/ask stream, so the spread is charged
the way the broker charges it rather than being subtracted afterwards:

    long  enters when ask >= buy_stop, fills at that ask
          exits  when bid crosses SL/TP, fills at that bid
    short enters when bid <= sell_stop, fills at that bid
          exits  when ask crosses SL/TP, fills at that ask

That asymmetry matters. On BREAK100 the spread is 5.00 and a 1R stop is ~53, so
a long is stopped after the bid falls ~R-5 but only reaches target after it
rises ~R+5. Any model that applies costs at the end instead of inside the fill
logic will overstate the win rate.
"""

from __future__ import annotations

import bisect
import math
import statistics as st
from dataclasses import dataclass, field
from enum import StrEnum

from break100.research.replay import BoxEvent

SECONDS_PER_DAY = 86_400


class Exit(StrEnum):
    """How a trade ended."""

    TP = "TP"
    SL = "SL"
    TRAIL = "TRAIL"
    TIMEOUT = "TIMEOUT"
    END_OF_DATA = "END_OF_DATA"


@dataclass(frozen=True, slots=True)
class Costs:
    """Broker friction. `slippage` is in price units, applied against the fill."""

    slippage: float = 0.0
    commission_per_lot: float = 0.0
    swap_per_day: float = 0.0


@dataclass(frozen=True, slots=True)
class Config:
    """Strategy knobs. Defaults reproduce the EA as currently shipped."""

    tp1_r: float = 1.0
    """TP1 as a multiple of the stop distance."""
    tp1_covers_costs: bool = False
    """Push TP1 out by the round-trip cost so a win nets the full tp1_r."""
    sl_buf: float = 0.15
    """Stop sits this many box-heights beyond the opposite rail."""
    trail_start_r: float = 0.0
    """Begin trailing once the trade is this many R in front. 0 disables."""
    trail_distance_r: float = 0.5
    """Trail this many R behind the best price reached."""
    breakeven_at_r: float = 0.0
    """Move the stop to entry + costs at this many R. 0 disables."""
    cooldown_bars: int = 0
    """Skip boxes arming within this many M30 bars of the last exit."""
    timeout_bars: int = 12
    """Close the position after this many bars regardless."""
    min_box_height: float = 0.0
    """Skip boxes shorter than this. Gap overshoot measured in R scales inversely
    with box size — a 100-unit gap is 2.2R against a 46-unit stop but 0.87R
    against a 115-unit one — so this is the main controllable cost lever."""
    max_entry_gap: float = 0.0
    """Reject a fill that gapped further than this past the stop price. 0 = off."""
    risk_fraction: float = 0.0025
    bar_seconds: int = 1800


@dataclass(frozen=True, slots=True)
class Trade:
    """One completed round trip."""

    entry_time: int
    exit_time: int
    direction: int
    entry: float
    stop: float
    target: float
    exit_price: float
    lots: float
    r_multiple: float
    pnl: float
    reason: Exit


@dataclass(frozen=True, slots=True)
class Report:
    """Headline performance of one configuration."""

    label: str
    trades: int
    wins: int
    losses: int
    win_rate: float
    roi: float
    total_pnl: float
    sharpe: float
    max_drawdown: float
    expectancy_r: float
    profit_factor: float
    avg_win_r: float
    avg_loss_r: float
    days: float
    sd_r: float = 0.0
    expectancy_t: float = 0.0
    """Expectancy in units of its own standard error. This, not ROI, decides."""
    equity_curve: list[tuple[int, float]] = field(default_factory=list)
    exits: dict[str, int] = field(default_factory=dict)

    def line(self) -> str:
        return (
            f"{self.label:<28}{self.trades:>7}{self.win_rate * 100:>8.1f}%"
            f"{self.roi * 100:>9.2f}%{self.sharpe:>8.2f}"
            f"{self.max_drawdown * 100:>8.2f}%{self.expectancy_r:>9.3f}"
            f"{self.expectancy_t:>8.2f}{self.profit_factor:>8.2f}"
        )


def noise_threshold(trials: int) -> float:
    """The t-stat the *best* of `trials` zero-edge configurations typically hits.

    Searching many variants over one dataset guarantees a winner even when every
    variant is worthless. The expected maximum of n standard normals grows like
    sqrt(2 ln n), so a result must clear this line before it is worth anything.
    """
    if trials <= 1:
        return 0.0
    return math.sqrt(2.0 * math.log(trials))


class TickBook:
    """Bid/ask arrays with time-indexed lookup."""

    __slots__ = ("time", "bid", "ask")

    def __init__(self, times: list[int], bids: list[float], asks: list[float]) -> None:
        self.time = times
        self.bid = bids
        self.ask = asks

    def __len__(self) -> int:
        return len(self.time)

    def index_at_or_after(self, utc_seconds: int) -> int:
        return bisect.bisect_left(self.time, utc_seconds * 1000)


def _normalize_lots(raw: float, vmin: float = 0.01, vmax: float = 8.0, step: float = 0.01) -> float:
    """Round volume DOWN to the broker step, matching B100NormalizeLotsDown."""
    if raw < vmin:
        return 0.0
    capped = min(raw, vmax)
    steps = math.floor((capped - vmin) / step + 1e-12)
    return vmin + steps * step


def _simulate_one(
    book: TickBook,
    event: BoxEvent,
    cfg: Config,
    costs: Costs,
    equity: float,
    spread_hint: float,
) -> Trade | None:
    """Walk ticks from the arm bar and resolve one straddle, or None if unfilled."""
    start = book.index_at_or_after(event.armed_bar + cfg.bar_seconds)
    if start >= len(book):
        return None
    deadline = event.armed_bar + cfg.bar_seconds * (1 + cfg.timeout_bars)

    height = event.cluster.height
    sl_dist = height * (1.0 + max(cfg.sl_buf, 0.0))
    if sl_dist <= 0.0:
        return None
    if cfg.min_box_height > 0.0 and height < cfg.min_box_height:
        return None

    direction = 0
    entry = 0.0
    entry_i = 0
    for i in range(start, len(book)):
        if book.time[i] // 1000 > deadline:
            return None
        if book.ask[i] >= event.buy_stop:
            if cfg.max_entry_gap > 0.0 and book.ask[i] - event.buy_stop > cfg.max_entry_gap:
                return None
            direction, entry, entry_i = 1, book.ask[i] + costs.slippage, i
            break
        if book.bid[i] <= event.sell_stop:
            if cfg.max_entry_gap > 0.0 and event.sell_stop - book.bid[i] > cfg.max_entry_gap:
                return None
            direction, entry, entry_i = -1, book.bid[i] - costs.slippage, i
            break
    if direction == 0:
        return None

    round_trip = spread_hint + 2.0 * costs.slippage
    stop = entry - direction * sl_dist
    target_dist = cfg.tp1_r * sl_dist + (round_trip if cfg.tp1_covers_costs else 0.0)
    target = entry + direction * target_dist

    lots = _normalize_lots((equity * cfg.risk_fraction) / sl_dist)
    if lots <= 0.0:
        return None

    best = entry
    exit_deadline = event.armed_bar + cfg.bar_seconds * (1 + cfg.timeout_bars * 2)
    for i in range(entry_i + 1, len(book)):
        t = book.time[i] // 1000
        # Longs are marked and exited on the bid; shorts on the ask.
        mark = book.bid[i] if direction > 0 else book.ask[i]
        gain = (mark - entry) * direction

        if gain > (best - entry) * direction:
            best = mark
        if cfg.breakeven_at_r > 0.0 and gain >= cfg.breakeven_at_r * sl_dist:
            be = entry + direction * round_trip
            stop = max(stop, be) if direction > 0 else min(stop, be)
        if cfg.trail_start_r > 0.0 and gain >= cfg.trail_start_r * sl_dist:
            trail = best - direction * cfg.trail_distance_r * sl_dist
            stop = max(stop, trail) if direction > 0 else min(stop, trail)

        hit_sl = mark <= stop if direction > 0 else mark >= stop
        hit_tp = mark >= target if direction > 0 else mark <= target
        if hit_sl or hit_tp or t > exit_deadline:
            px = mark
            if hit_tp:
                reason = Exit.TP
            elif hit_sl:
                reason = Exit.TRAIL if cfg.trail_start_r > 0.0 and gain > 0 else Exit.SL
            else:
                reason = Exit.TIMEOUT
            move = (px - entry) * direction
            pnl = move * lots - costs.commission_per_lot * lots
            return Trade(
                entry_time=book.time[entry_i] // 1000,
                exit_time=t,
                direction=direction,
                entry=entry,
                stop=stop,
                target=target,
                exit_price=px,
                lots=lots,
                r_multiple=move / sl_dist,
                pnl=pnl,
                reason=reason,
            )
    return None


def run(
    label: str,
    events: list[BoxEvent],
    book: TickBook,
    cfg: Config,
    costs: Costs,
    spread_hint: float,
    starting_equity: float = 10_000.0,
) -> Report:
    """Simulate every box event in order and summarise the result."""
    equity = starting_equity
    curve: list[tuple[int, float]] = []
    trades: list[Trade] = []
    cooldown_until = 0

    for event in sorted(events, key=lambda e: e.armed_bar):
        if event.armed_bar < cooldown_until:
            continue
        trade = _simulate_one(book, event, cfg, costs, equity, spread_hint)
        if trade is None:
            continue
        equity += trade.pnl
        trades.append(trade)
        curve.append((trade.exit_time, equity))
        if cfg.cooldown_bars > 0:
            cooldown_until = trade.exit_time + cfg.cooldown_bars * cfg.bar_seconds

    return summarise(label, trades, curve, starting_equity, equity)


def summarise(
    label: str,
    trades: list[Trade],
    curve: list[tuple[int, float]],
    starting_equity: float,
    final_equity: float,
) -> Report:
    """Turn a trade list into headline metrics."""
    n = len(trades)
    if n == 0:
        return Report(label, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

    wins = [t for t in trades if t.pnl > 0]
    losses = [t for t in trades if t.pnl <= 0]
    gross_win = math.fsum(t.pnl for t in wins)
    gross_loss = abs(math.fsum(t.pnl for t in losses))

    peak = starting_equity
    max_dd = 0.0
    for _, eq in curve:
        peak = max(peak, eq)
        if peak > 0:
            max_dd = max(max_dd, (peak - eq) / peak)

    # Sharpe from daily equity changes, annualised for a 24/7 instrument.
    by_day: dict[int, float] = {}
    prev = starting_equity
    for ts, eq in curve:
        by_day[ts // SECONDS_PER_DAY] = eq
    daily_returns: list[float] = []
    for day in sorted(by_day):
        eq = by_day[day]
        if prev > 0:
            daily_returns.append((eq - prev) / prev)
        prev = eq
    sharpe = 0.0
    if len(daily_returns) > 1:
        sd = st.pstdev(daily_returns)
        if sd > 0:
            sharpe = st.mean(daily_returns) / sd * math.sqrt(365)

    span = (trades[-1].exit_time - trades[0].entry_time) / SECONDS_PER_DAY if n > 1 else 0.0
    exits: dict[str, int] = {}
    for t in trades:
        exits[t.reason.value] = exits.get(t.reason.value, 0) + 1

    r_values = [t.r_multiple for t in trades]
    expectancy = math.fsum(r_values) / n
    sd_r = st.pstdev(r_values) if n > 1 else 0.0
    expectancy_t = expectancy / (sd_r / math.sqrt(n)) if sd_r > 0 and n > 1 else 0.0

    return Report(
        label=label,
        trades=n,
        wins=len(wins),
        losses=len(losses),
        win_rate=len(wins) / n,
        roi=(final_equity - starting_equity) / starting_equity,
        total_pnl=final_equity - starting_equity,
        sharpe=sharpe,
        max_drawdown=max_dd,
        expectancy_r=expectancy,
        profit_factor=(gross_win / gross_loss) if gross_loss > 0 else float("inf"),
        avg_win_r=math.fsum(t.r_multiple for t in wins) / len(wins) if wins else 0.0,
        avg_loss_r=math.fsum(t.r_multiple for t in losses) / len(losses) if losses else 0.0,
        days=span,
        sd_r=sd_r,
        expectancy_t=expectancy_t,
        equity_curve=curve,
        exits=exits,
    )


HEADER = (
    f"{'configuration':<28}{'trades':>7}{'win%':>9}{'ROI':>9}"
    f"{'Sharpe':>8}{'MaxDD':>8}{'exp(R)':>9}{'t':>8}{'PF':>8}"
)
