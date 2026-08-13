# Security and Broker-Order-Path Audit

## Audit scope

The 2026-08-13 Gate G0 audit recursively inspected the repository, including
hidden files and Git metadata, for MQL5 and Python broker execution surfaces.
The search covered `OrderSend`, `OrderSendAsync`, `OrderCheck`,
`MqlTradeRequest`, `CTrade`, trade actions, position open/close, `Buy`, `Sell`,
MetaTrader5 bindings, and `order_send` patterns.

## Finding

No project source existed and no broker-order keyword or submission path was
found. Consequently, an accidental Live order is unreachable in this baseline.

This is **not** evidence that Observe or Shadow are structurally isolated. Those
modes do not yet exist. Structural isolation requires separate dependency
boundaries and tests proving non-trading modes cannot import or invoke any
broker execution adapter.

## Required architecture controls

- Indicator contains no execution dependency.
- Observe/Shadow package graph contains no broker execution dependency.
- Demo and Live use distinct adapters and configuration namespaces.
- The adapter accepts Mtrading identity only and has no alternative broker path.
- Demo adapter rejects non-Demo accounts before `OrderCheck`/submission.
- Live adapter defaults disabled and requires G5 evidence, owner approval,
  account/symbol allowlists, an unexpired control lease, and canary caps.
- Static scans and integration tests verify the boundaries at every release.

## Gate conclusion

- Accidental order path in the audited baseline: `NONE FOUND`.
- Implemented Observe/Shadow isolation: `NOT YET PROVEN`.
- Demo/Live readiness: `NO-GO`.
