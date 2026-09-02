"""Bar-level replay of the box arm/fill/timeout state machine.

Mirrors `B100BoxOnTick` in `Box.mqh`. The EA resolves fills on ticks; a bar-level
replay cannot know whether a bar's high or its low came first. Where a single
rail is touched the fill is unambiguous. Where both are touched inside one bar
the outcome is genuinely undetermined from OHLC, and this module labels it
`AMBIGUOUS` rather than guessing — which matches what the EA does on its
close-path (`CENSORED_OR_AMBIGUOUS`) and keeps the bias out of the statistics.

Tick-level refinement of the ambiguous cases is a separate pass.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from break100.research.boxdetect import (
    BoxParams,
    Cluster,
    find_cluster_at,
    h4_span_at,
    impulse_before,
    range_pattern,
)
from break100.research.series import Series

M30_SECONDS = 30 * 60


class Outcome(StrEnum):
    """Terminal state of one armed box."""

    BREAKOUT_UP = "BREAKOUT_UP"
    BREAKOUT_DOWN = "BREAKOUT_DOWN"
    AMBIGUOUS = "AMBIGUOUS"
    TIMEOUT = "TIMEOUT"
    UNRESOLVED = "UNRESOLVED"


@dataclass(frozen=True, slots=True)
class BoxFeatures:
    """Shape and context of a box at the moment it armed. Model inputs."""

    touches_hi: int
    touches_lo: int
    close_loc: float
    compress: float
    h_vs_h4: float
    imp_dir: int
    imp_vs_box: float
    box_at: float
    phase: str
    hour_utc: int
    dow: int
    spread_pts: int


@dataclass(frozen=True, slots=True)
class BoxEvent:
    """One armed box and how it resolved."""

    armed_bar: int
    cluster: Cluster
    buy_stop: float
    sell_stop: float
    features: BoxFeatures
    outcome: Outcome
    resolved_bar: int
    bars_waited: int


@dataclass(slots=True)
class _Armed:
    """Mutable state while a box is live."""

    cluster: Cluster
    armed_bar: int
    buy_stop: float
    sell_stop: float
    features: BoxFeatures
    waited: int = 0


def _dow(utc: int) -> int:
    """Day of week, 0 = Sunday, matching MQL5's MqlDateTime.day_of_week."""
    return ((utc // 86400) + 4) % 7


def replay(
    m30: Series,
    h4: Series,
    params: BoxParams,
    point: float,
) -> list[BoxEvent]:
    """Replay the M30 series and return every box that armed, with its outcome."""
    events: list[BoxEvent] = []
    lock_bar = 0
    live: _Armed | None = None

    # cursor is the forming bar, so shift 1 is the bar that just closed.
    for cursor in range(len(m30)):
        m30.cursor = cursor
        bar = m30.at(1)
        if bar is None or bar.time == 0:
            continue
        closed_time = bar.time

        if live is not None:
            live.waited += 1
            hit_buy = bar.high >= live.buy_stop
            hit_sell = bar.low <= live.sell_stop

            outcome: Outcome | None = None
            if hit_buy and hit_sell:
                outcome = Outcome.AMBIGUOUS
            elif hit_buy:
                outcome = Outcome.BREAKOUT_UP
            elif hit_sell:
                outcome = Outcome.BREAKOUT_DOWN
            elif live.waited >= max(2, params.timeout_bars):
                outcome = Outcome.TIMEOUT

            if outcome is not None:
                events.append(
                    BoxEvent(
                        armed_bar=live.armed_bar,
                        cluster=live.cluster,
                        buy_stop=live.buy_stop,
                        sell_stop=live.sell_stop,
                        features=live.features,
                        outcome=outcome,
                        resolved_bar=closed_time,
                        bars_waited=live.waited,
                    )
                )
                lock_bar = closed_time
                live = None
            continue

        if lock_bar != 0 and closed_time <= lock_bar:
            continue

        span = h4_span_at(h4, closed_time + M30_SECONDS)
        cluster = find_cluster_at(m30, 1, params, span)
        if cluster is None:
            continue
        if cluster.t_right != 0 and cluster.t_right <= lock_bar:
            continue

        pattern = range_pattern(m30, 1, cluster.bars, cluster.high, cluster.low, span)
        imp = impulse_before(m30, 1, cluster.bars, cluster.height, max(params.impulse_k, 1.2))
        buy_stop, sell_stop = cluster.stops(point)
        live = _Armed(
            cluster=cluster,
            armed_bar=closed_time,
            buy_stop=buy_stop,
            sell_stop=sell_stop,
            features=BoxFeatures(
                touches_hi=pattern.touches_hi,
                touches_lo=pattern.touches_lo,
                close_loc=pattern.close_loc,
                compress=pattern.compress,
                h_vs_h4=pattern.h_vs_h4,
                imp_dir=imp.direction if imp else 0,
                imp_vs_box=imp.vs_box if imp else 0.0,
                box_at=imp.box_at if imp else 0.5,
                phase="IMPULSE_THEN_RANGE" if imp else "RANGE_THEN_BREAK",
                hour_utc=(closed_time % 86400) // 3600,
                dow=_dow(closed_time),
                spread_pts=bar.spread,
            ),
        )

    if live is not None:
        events.append(
            BoxEvent(
                armed_bar=live.armed_bar,
                cluster=live.cluster,
                buy_stop=live.buy_stop,
                sell_stop=live.sell_stop,
                features=live.features,
                outcome=Outcome.UNRESOLVED,
                resolved_bar=0,
                bars_waited=live.waited,
            )
        )
    return events
