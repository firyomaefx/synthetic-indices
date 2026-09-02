# BREAK100 backtest — 20 configurations, full tick history

Run: `py -3.13 tools/backtest_break100.py`
Data: 3,559,792 ticks, 42 days (2026-07-22 → 2026-09-01), complete 1 Hz record.
Fills resolved against the real bid/ask stream. Risk 0.25%/trade, £10,000 start.

## M30 boxes / H4 reference — 124 armed boxes

| configuration | trades | win% | ROI | Sharpe | MaxDD | exp(R) | t | PF |
|---|---|---|---|---|---|---|---|---|
| baseline (as shipped) | 122 | 46.7% | −4.90% | −2.76 | 10.11% | −0.164 | −0.84 | 0.84 |
| TP1 covers costs | 122 | 45.9% | −5.07% | −2.87 | 10.43% | −0.169 | −0.86 | 0.84 |
| TP1 = 2R | 122 | 32.8% | −11.26% | −4.89 | 16.75% | −0.390 | −1.75 | 0.70 |
| TP1 2R + costs | 122 | 31.1% | −12.06% | −5.25 | 17.51% | −0.419 | −1.86 | 0.68 |
| breakeven @1R | 122 | 31.1% | −10.52% | −4.70 | 16.05% | −0.362 | −1.65 | 0.71 |
| trail from 1R | 122 | 45.1% | −6.92% | −3.72 | 11.63% | −0.233 | −1.17 | 0.78 |
| trail tight 0.25R | 122 | 50.0% | −5.60% | −3.24 | 10.90% | −0.187 | −1.00 | 0.81 |
| cooldown 4 bars | 89 | 31.5% | −8.90% | −4.78 | 12.19% | −0.415 | −1.57 | 0.68 |
| trail + cooldown | 91 | 42.9% | −5.47% | −3.74 | 8.02% | −0.248 | −1.10 | 0.77 |
| everything on | 91 | 42.9% | −5.59% | −3.82 | 8.14% | −0.253 | −1.13 | 0.76 |

## M15 boxes / H1 reference — 153 armed boxes

| configuration | trades | win% | ROI | Sharpe | MaxDD | exp(R) | t | PF |
|---|---|---|---|---|---|---|---|---|
| baseline (as shipped) | 150 | 47.3% | −3.90% | −1.60 | 9.26% | −0.096 | −0.43 | 0.91 |
| TP1 covers costs | 150 | 46.7% | −3.97% | −1.64 | 9.33% | −0.099 | −0.44 | 0.91 |
| TP1 = 2R | 150 | 38.0% | −5.33% | −1.70 | 12.55% | −0.137 | −0.54 | 0.90 |
| TP1 2R + costs | 150 | 36.7% | −5.56% | −1.76 | 11.74% | −0.141 | −0.55 | 0.90 |
| breakeven @1R | 150 | 39.3% | −2.79% | −0.84 | 10.68% | −0.067 | −0.27 | 0.94 |
| trail from 1R | 150 | 46.0% | −3.21% | −1.18 | 8.42% | −0.078 | −0.34 | 0.93 |
| trail tight 0.25R | 150 | 52.0% | −4.12% | −1.84 | 8.53% | −0.103 | −0.48 | 0.90 |
| **cooldown 4 bars** | 121 | 41.3% | **+0.70%** | 0.35 | 9.50% | +0.035 | **+0.12** | 1.02 |
| trail + cooldown | 122 | 48.4% | −0.18% | 0.05 | 7.01% | +0.005 | +0.02 | 1.00 |
| everything on | 122 | 48.4% | **+0.21%** | 0.19 | 7.00% | +0.018 | +0.07 | 1.01 |

## Verdict

**2 of 20 configurations made money. Neither means anything.**

With 20 trials on one dataset, the luckiest of 20 *genuinely worthless* variants
would typically reach **t = 2.45** (`sqrt(2·ln 20)`). The best observed is
**t = +0.12** — twenty times short of the bar, and far below what pure chance
across 20 trials normally produces. The +0.70% is not a small edge; it is
indistinguishable from zero, and weaker than luck would usually manage.

## The win rate confirms the martingale, independently

Median M30 box height is 58, so the stop distance is 58 × 1.15 ≈ **66.7**.

A long fills at the ask; the bid is 5.00 below it. The stop is then only
`R − 5 = 61.7` below the bid, while the target is `R + 5 = 71.7` above it. On a
driftless walk the chance of touching the near barrier first is:

```
P(win) = (R − 5) / (2R) = 61.7 / 133.4 = 46.25%
```

**Measured baseline win rate: 46.7%.** The random-walk prediction lands within
half a point. Nothing about the strategy is generating that number — the geometry
of the spread is.

Theoretical expectancy from that alone is −0.075R; measured is −0.164R. The gap
is entry slippage, which this run did not isolate: a stop order fills at whatever
ask exists once the level is crossed, and on BREAK100 the moves large enough to
break a box are frequently the 50–300 unit spikes. **The same spikes that trigger
the entry also supply the worst fills.** Worth measuring directly before relying
on that explanation.

## What trail and cooldown actually did

- **Trailing** raised the win rate (50.0% and 52.0%) and cut drawdown, but ROI
  stayed negative in every case. It reshapes the outcome distribution; it cannot
  move its mean.
- **Cooldown** was the only thing that helped, and only because it *trades less*
  — 122 trades became 89 on M30, 150 became 121 on M15. Cutting trade count cuts
  total spread paid. It reduces the bleed rate; it does not create edge. Taken to
  its limit, zero trades gives exactly 0.00% and that is the ceiling.

That is the whole picture in one line: **on this instrument every knob trades one
kind of loss for another, and the only lever that helps is not trading.**
