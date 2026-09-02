# Data ceiling — measured 2026-09-02

Pulled directly from the running Mtrading terminal via the MetaTrader5 Python
bridge (`tools/export_history.py`, read-only). This is not a sampling limit we
chose; it is everything the broker retains for BREAK100.

## What exists

| Timeframe | Bars | Span | Coverage |
|---|---|---|---|
| M1 | 59,333 | 2026-07-22 → 2026-09-01 | 100% |
| M5 | 11,867 | same | 100% |
| M15 | 3,956 | same | 100% |
| M30 | **1,979** | same | 100% |
| H1 | 990 | same | 100% |
| H4 | 249 | same | 100% |
| Ticks | 3,559,730 | same | 1 Hz, complete |

**41.2 days. That is the hard ceiling.** Requesting more returns the same span —
`copy_rates_from_pos` with any count above 1,979 on M30 returns 1,979. (Note
`count = 100000` errors with `Invalid params`; 99,999 is the real cap.)

The tick file is exactly 86,400 rows per full day — this synthetic emits one
tick per second, so tick history is a complete record rather than a sample.
Intrabar path can therefore be reconstructed to the second.

## Box events available

Measured with the ported detector at default parameters:

| Variant | Bars | Events | Up | Down | Ambiguous | Timeout | Rate |
|---|---|---|---|---|---|---|---|
| M30 boxes, H4 reference | 2,019 | **131** | 61 | 59 | 4 | 6 | 0.065/bar |
| M15 boxes, H4 reference | 4,029 | **350** | 154 | 153 | 3 | 39 | 0.087/bar |
| M15 boxes, H1 reference | 4,029 | 156 | 80 | 60 | 2 | 14 | 0.039/bar |

The M30 and M15 variants observe the **same 41 days of price**, so their events
are not independent. Pooling them to reach ~481 would badly understate
uncertainty.

## Consequences

1. **The plan's 2,000-event bar is unreachable** from broker history. It needs
   ~1.8 years; 41 days exist. The 500-event provisional floor is only reachable
   by using the M15 variant (350) — and that is a *different* strategy, not more
   samples of the M30 one.
2. **We are powered to detect a large effect, not a modest one.** With 350
   events split 50/25/25, the holdout carries ~88. Separating a 55% win rate
   from 50% needs several hundred. Any marginal result will not survive the
   trial-count penalty.
3. **Direction is ~50/50 in every variant** (50.8/49.2 on M30, 50.2/49.8 on
   M15). This is the expected result for a straddle and it independently
   confirms the quarantined v1 policy — which claimed `p_dn = 0.0035` — was
   corruption, not signal. It also means **edge cannot live in direction
   prediction.** If it exists it is in payoff asymmetry: whether winners run
   further than losers' stops, after costs.
4. **Waiting helps slowly.** Forward capture adds ~3.2 M30 events/day
   (~8.5 M15/day). Doubling the M15 sample takes roughly another 41 days.
   The broker's 41-day window rolls, so history must be captured as it passes —
   which is what Capture.mqh is already doing.

## Where this leaves the research

The question worth spending the sample on is not "which way will it break"
(answered: a coin flip) but "is the after-cost R distribution positive". The
1 Hz tick record is enough to measure that precisely for 131–350 events, which
is a real, if provisional, answer.
