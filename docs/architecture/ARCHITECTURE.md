# Architecture

## Trust and responsibility boundaries

1. Data plane: immutable UTC bid/ask ticks and broker metadata.
2. Research plane: causal events/features/labels, statistics, ML/RL training,
   validation, and versioned model registry.
3. Decision plane: frozen inference, uncertainty, SafeEV, health and risk gates.
4. Execution plane: distinct Shadow, Demo, and locked Live adapters.
5. Presentation plane: MQL5 Indicator and minimal operational dashboard.

## Broker scope

Only Mtrading is supported. A future Mtrading adapter must supply
independently-observed broker identity, account identifier, account environment,
and symbol to the policy boundary. It has no non-Mtrading fallback. Exact
account and symbol allowlists remain empty by default and must be injected by
the owner-controlled runtime configuration, never source control.

The Indicator never imports execution code. Observe and Shadow depend only on
non-trading interfaces. Demo and Live adapters are separate modules loaded only
after state-specific validation.

## Planned components

- `src/break100/data`: collection, schemas, provenance and replay.
- `src/break100/events`: causal channel, touch and competing-risk labels.
- `src/break100/research`: statistical edge gateway and validation.
- `src/break100/models`: calibration, uncertainty, ONNX and registry.
- `src/break100/decision`: SafeEV, abstention and deterministic policy.
- `src/break100/risk`: sizing, limits and kill switches.
- `src/break100/shadow`: fills, ledger and Shadow reconciliation.
- `src/break100/execution/demo`: verified Demo-only broker adapter.
- `src/break100/execution/live`: locked owner/lease/allowlist adapter.
- `src/break100/broker/mtrading.py`: Mtrading-only identity and allowlist
  policy; deliberately no MT5 or order-submission dependency.
- `mql5/Indicators`: visual-only BREAK100 Indicator.
- `mql5/Experts`: stateful EA with isolated execution integration.
- `evidence`: immutable manifests and gate outputs, excluding secrets.

## Decision flow

`tick -> causal event -> feature snapshot -> frozen model -> calibrated outcome`
`-> uncertainty -> after-cost SafeEV -> health/risk gates -> NO_TRADE or action`
`-> mode adapter -> ledger/audit/reconciliation`

Any invalid or stale input terminates at `NO_TRADE` and a reason-coded audit
event. Hot-swap is permitted only while flat and after checksum/schema checks.

## Live control

Source code alone never enables Live. Activation requires a completed G5 gate,
explicit owner action, verified approved account/symbol, time-limited signed or
locally authenticated control lease, flat/safe state, and caps. Expiry or any
critical failure blocks new entries automatically.
