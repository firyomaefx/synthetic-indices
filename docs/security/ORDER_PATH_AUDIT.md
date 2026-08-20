# Security and Broker-Order-Path Audit

## Audit scope

The 2026-08-13 Gate G0 audit recursively inspected the repository, including
hidden files and Git metadata, for MQL5 and Python broker execution surfaces.
The search covered `OrderSend`, `OrderSendAsync`, `OrderCheck`,
`MqlTradeRequest`, `CTrade`, trade actions, position open/close, `Buy`, `Sell`,
MetaTrader5 bindings, and `order_send` patterns.

## Finding (updated 2026-08-21)

`mql5/Include/Break100/DemoExec.mqh` contains `OrderSend` for **DEMO_AUTO**
(market send for channel; pending BUY_STOP/SELL_STOP OCO for M30 box).
Runtime guards: `B100BrokerOrderIntentPermitted` requires `B100_DEMO` **and**
`ACCOUNT_TRADE_MODE_DEMO`. Real accounts requesting DEMO are forced OBSERVE.
LIVE remains `LIVE_DISABLED` in `Mode.mqh` with no Live OrderSend path.
Telegram uses WebRequest only; token is not in source.

Observe/Shadow still must not send: intent is false unless mode is DEMO.

This is **not** evidence that Observe or Shadow are structurally isolated. Those
modes do not yet exist. Structural isolation requires separate dependency
boundaries and tests proving non-trading modes cannot import or invoke any
broker execution adapter.

## Required architecture controls

- Indicator contains no execution dependency.
- Observe/Shadow package graph contains no broker execution dependency.
- Demo and Live use distinct adapters and configuration namespaces.
- Demo adapter rejects non-Demo accounts before `OrderCheck`/submission.
- Live adapter defaults disabled and requires G5 evidence, owner approval,
  account/symbol allowlists, an unexpired control lease, and canary caps.
- Static scans and integration tests verify the boundaries at every release.

## Gate conclusion

- Accidental Live order path: `NONE` (LIVE still source-disabled).
- Demo OrderSend path: `PRESENT` in DemoExec, demo-account gated.
- Observe/Shadow isolation: runtime intent false; DemoExec is still linked into the EA binary.
- Live readiness: `NO-GO`.
- Demo auto: `LIMITED GO` pending demo-account evidence pack (not yet run in this workspace).

