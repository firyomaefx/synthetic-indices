# Test and Validation Plan

## Automated levels

- L0 contracts: required files, schemas, manifests, mode defaults.
- L1 units: channels, causal features/labels, SafeEV, sizing, state transitions.
- L2 integrations: tick-to-decision, registry-to-inference, Shadow ledger, risk
  gates, audit/recovery.
- L3 components: deterministic tick replay with external services mocked.
- BF1 properties: transformations and numerical invariants.
- BF4 chaos: corrupt files, stale ticks, ONNX failure, broker rejection.
- BF9 security: secret redaction, allowlists, lease and path safety.

## Required commands

Commands will be fixed in the release manifest after scaffolding. At minimum:

- Python formatting, linting, type checking, and full test suite.
- MQL5 Indicator and EA MetaEditor compilation with log inspection and `.ex5`
  artifact checks.
- Python/ONNX parity and deterministic replay commands.
- Order-path static audit proving Observe/Shadow isolation.

## Model validation

Use chronological purged/embargoed walk-forward splits. Compare constant hazard,
regularised multinomial, and discrete hazard baselines before a boosted model.
Include spread, commission, slippage, latency, gaps, severe cost stress, block
bootstrap/Monte Carlo, calibration, abstention, weekly/regime stability, and an
IID synthetic negative control that must not fabricate edge.

## External validation

Demo and Live Canary evidence requires approved real sessions. Missing external
evidence is a recorded skip/blocker, never a pass.

