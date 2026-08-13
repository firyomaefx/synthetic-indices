# Scope Statement

## In scope

- Causal tick collection, channel events, labels, and feature snapshots.
- Statistical edge tests, calibrated ML, uncertainty, and SafeEV.
- Offline RL research for execution/exit optimisation after a deterministic
  baseline is proven.
- Versioned model registry and Python/ONNX parity checks.
- MQL5 indicator, Observe/Shadow EA, isolated Demo adapter, and locked Live
  adapter for Mtrading only.
- Shadow ledger, fill simulation, risk engine, kill switches, reconciliation,
  recovery, rollback, audit logs, tests, and operating documentation.

## Out of scope

- Guaranteed profitability or fabricated backtest, Shadow, Demo, or Live data.
- Real order-book, institutional-flow, or real-volume claims without verified
  broker data.
- CAPTCHA bypass, credential storage, automatic owner approval, or automatic
  promotion of a freshly trained model.
- Other brokers, including broker-specific compatibility layers or fallbacks.
- Bounce trading in Live before independent rare-gap tail validation.

## Acceptance boundary

Completion is always scoped to the highest gate supported by actual evidence.
Lack of data or external broker evidence is a valid `NO-GO`, not permission to
weaken a gate.
