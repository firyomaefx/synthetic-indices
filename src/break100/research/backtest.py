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

from break100.research.policy import quantile
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
    # --- tick path, measured on the same marks the exit uses (bid long / ask short).
    # r_multiple alone says where the trade ended; these say where it went. An exit
    # rule can only ever give back what the path offered, so a strategy with no
    # favourable excursion is not fixable by re-tuning targets.
    mfe_r: float = 0.0
    """Maximum favourable excursion, in R. Never negative."""
    mae_r: float = 0.0
    """Maximum adverse excursion, in R. Never positive."""
    seconds_to_mfe: int = 0
    """Seconds from fill to the favourable extreme. On a winner this is time-to-win;
    on a loser it is when the trade was best placed before it turned over."""
    seconds_to_mae: int = 0
    """Seconds from fill to the adverse extreme. On a winner this is when the heat
    peaked; on a loser it is time-to-stop.

    Note the exit tick is itself an extreme — a TP exit sets the MFE and an SL exit
    sets the MAE — so asking which extreme came *first* mostly just restates the
    exit type. The timings are kept because they are informative about horizon;
    their ordering is not, so nothing derives a signal from it.
    """
    entry_slippage_r: float = 0.0
    """Fill worse than the stop-order price, in R. Positive = paid away."""


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
    trade_log: list[Trade] = field(default_factory=list)
    """Every completed round trip this configuration produced, in exit order.

    Kept so callers can run `asymmetry()` on the exact trades a Report summarised,
    without re-simulating. Named `trade_log`, not `trades` -- `trades` above is
    already the integer count.
    """

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

    # The stop order was resting at buy_stop/sell_stop; `entry` is what the book
    # actually paid once the level was crossed. BACKTEST_RESULTS.md flags this gap
    # as the unmeasured term between theoretical (-0.075R) and measured (-0.164R)
    # expectancy, so carry it per trade instead of inferring it.
    intended = event.buy_stop if direction > 0 else event.sell_stop
    entry_slippage_r = ((entry - intended) * direction) / sl_dist

    entry_t = book.time[entry_i] // 1000
    best = entry
    worst = entry
    t_best = entry_t
    t_worst = entry_t
    exit_deadline = event.armed_bar + cfg.bar_seconds * (1 + cfg.timeout_bars * 2)
    for i in range(entry_i + 1, len(book)):
        t = book.time[i] // 1000
        # Longs are marked and exited on the bid; shorts on the ask.
        mark = book.bid[i] if direction > 0 else book.ask[i]
        gain = (mark - entry) * direction

        if gain > (best - entry) * direction:
            best = mark
            t_best = t
        if gain < (worst - entry) * direction:
            worst = mark
            t_worst = t
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
                mfe_r=((best - entry) * direction) / sl_dist,
                mae_r=((worst - entry) * direction) / sl_dist,
                seconds_to_mfe=t_best - entry_t,
                seconds_to_mae=t_worst - entry_t,
                entry_slippage_r=entry_slippage_r,
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


@dataclass(frozen=True, slots=True)
class Asymmetry:
    """Payoff shape of one configuration, measured from the tick path.

    `BACKTEST_RESULTS.md` established that direction on BREAK100 is a coin flip:
    the 46.7% measured win rate is the 46.25% a driftless walk predicts from spread
    geometry. That closes off direction prediction and leaves exactly one question —
    whether winners run further than losers' stops, after costs. These are the
    numbers that answer it.

    `edge_ratio` is the one to read first. It compares how far price travelled in
    favour against how far it travelled against, and it does not depend on where
    the exits were placed, so it separates "this instrument offers nothing" from
    "the exits are badly tuned". At 1.0 the path is symmetric and no exit rule can
    manufacture an edge from it.
    """

    trades: int
    edge_ratio: float
    """mean(MFE) / mean(|MAE|). Exit-rule independent. 1.0 = symmetric path."""
    capture: float
    """mean(R) / mean(MFE). How much of the offered move the exits actually took."""
    payoff_ratio: float
    """avg win R / |avg loss R|."""
    tail_ratio: float
    """q90(R) / |q10(R)|. Asymmetry in the tails rather than the averages."""
    mean_mfe_r: float
    mean_mae_r: float
    mae_when_win: float
    """Mean MAE of winners. If winners dip much less first, entry timing matters."""
    mae_when_loss: float
    mfe_when_loss: float
    """Mean MFE of losers. How much was on the table before they turned over."""
    median_seconds_to_mfe: float
    """Median time from fill to the favourable extreme — how fast the trade works."""
    median_seconds_to_mae: float
    """Median time from fill to the adverse extreme — how long it bleeds."""
    mean_slippage_r: float
    """Mean entry fill worse than the resting stop price, in R."""
    median_r: float

    def line(self) -> str:
        return (
            f"{self.trades:>7}{self.edge_ratio:>9.3f}{self.capture:>9.3f}"
            f"{self.payoff_ratio:>9.3f}{self.tail_ratio:>9.3f}"
            f"{self.mean_mfe_r:>9.3f}{self.mean_mae_r:>9.3f}"
            f"{self.median_seconds_to_mfe:>9.0f}{self.median_seconds_to_mae:>9.0f}"
            f"{self.mean_slippage_r:>9.3f}"
        )

    @staticmethod
    def header() -> str:
        return (
            f"{'trades':>7}{'edge':>9}{'capture':>9}{'payoff':>9}{'tail':>9}"
            f"{'mfe_r':>9}{'mae_r':>9}{'s_mfe':>9}{'s_mae':>9}{'slip_r':>9}"
        )


def asymmetry(trades: list[Trade]) -> Asymmetry:
    """Measure payoff asymmetry from the recorded tick paths.

    Zero-safe throughout: a denominator that cannot be formed yields 0.0 rather
    than an exception or an infinity, so a thin configuration reports a flat
    result instead of poisoning a comparison table.
    """
    n = len(trades)
    if n == 0:
        return Asymmetry(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

    r_values = [t.r_multiple for t in trades]
    mfes = [t.mfe_r for t in trades]
    maes = [abs(t.mae_r) for t in trades]
    mean_mfe = math.fsum(mfes) / n
    mean_mae = math.fsum(maes) / n
    mean_r = math.fsum(r_values) / n

    wins = [t for t in trades if t.pnl > 0]
    losses = [t for t in trades if t.pnl <= 0]
    avg_win = math.fsum(t.r_multiple for t in wins) / len(wins) if wins else 0.0
    avg_loss = math.fsum(t.r_multiple for t in losses) / len(losses) if losses else 0.0

    q90 = quantile(r_values, 0.90)
    q10 = quantile(r_values, 0.10)

    return Asymmetry(
        trades=n,
        edge_ratio=(mean_mfe / mean_mae) if mean_mae > 0 else 0.0,
        capture=(mean_r / mean_mfe) if mean_mfe > 0 else 0.0,
        payoff_ratio=(avg_win / abs(avg_loss)) if avg_loss < 0 else 0.0,
        tail_ratio=(q90 / abs(q10)) if q10 < 0 else 0.0,
        mean_mfe_r=mean_mfe,
        mean_mae_r=-mean_mae,
        mae_when_win=(math.fsum(t.mae_r for t in wins) / len(wins)) if wins else 0.0,
        mae_when_loss=(math.fsum(t.mae_r for t in losses) / len(losses)) if losses else 0.0,
        mfe_when_loss=(math.fsum(t.mfe_r for t in losses) / len(losses)) if losses else 0.0,
        median_seconds_to_mfe=quantile([float(t.seconds_to_mfe) for t in trades], 0.50),
        median_seconds_to_mae=quantile([float(t.seconds_to_mae) for t in trades], 0.50),
        mean_slippage_r=math.fsum(t.entry_slippage_r for t in trades) / n,
        median_r=quantile(r_values, 0.50),
    )


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
        trade_log=trades,
    )


HEADER = (
    f"{'configuration':<28}{'trades':>7}{'win%':>9}{'ROI':>9}"
    f"{'Sharpe':>8}{'MaxDD':>8}{'exp(R)':>9}{'t':>8}{'PF':>8}"
)
