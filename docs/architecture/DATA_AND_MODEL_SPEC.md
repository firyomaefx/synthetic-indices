# Data, Feature, Label, and Model Specification

## Time and raw data

- Persist UTC timestamps with integer precision and explicit source/provenance.
- Store bid, ask, spread, symbol properties, tick flags, and arrival metadata.
- Raw data is append-only; derived datasets reference immutable source hashes.

## Causal channel and touch

- Centre: causal robust state-space/Kalman estimate.
- Half-width: causal rolling quantile or median-absolute-deviation estimate.
- Touch distance: `max(2 * spread, 0.05 * channel_width)` initially.
- A historical value may use information available at or before its timestamp
  only.

## Label contract

Mutually exclusive outcomes are `BREAKOUT_UP`, `BREAKOUT_DOWN`, `BOUNCE`, and
`CENSORED_OR_AMBIGUOUS`. A versioned label manifest records penetration,
persistence, centre-return, MFE/MAE, and maximum-horizon rules. Overlapping
label windows require purging and embargo.

## Features

Only decision-time values are valid: touch/breakout counts and timing, side
sequences, channel geometry, approach dynamics, tick-sign runs, causal
transition/autocorrelation/entropy/MI estimates, prior event magnitudes,
bid/ask spread and arrivals, volatility, regime, and change-point state.

## Statistical gateway

Compare constant breakout hazard with state-conditioned hazard and include runs,
Ljung-Box, BDS, variance ratio, transition stability, permutation MI,
entropy-rate, conditional hazard, inter-event, change-point, and corrected
multiple tests. Failure to improve stably after costs returns `NO_EDGE`.

## Model sequence

1. Constant-probability benchmark.
2. Regularised multinomial and discrete-time hazard baselines.
3. Auditable boosted trees for class, direction, MFE/MAE, and holding time.
4. Causal sequence challenger only with sufficient data and net improvement.
5. Conservative offline RL challenger only after deterministic execution data.

Probabilities are calibrated out of sample. Leakage-safe conformal or equivalent
uncertainty produces abstention. Every manifest includes data/feature/label
versions, split definition, costs, metrics, checksum, environment, and approval.

## SafeEV contract

For each action, expected payoff includes spread, commission, slippage, latency,
and tail loss. `SafeEV` is a conservative lower confidence bound. An action is
eligible only when `SafeEV > 0` and all health/risk gates pass; otherwise the
decision is `NO_TRADE`.

