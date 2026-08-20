# Current-State and Capability Report

Updated 2026-08-21 after v1.70 DEMO_AUTO adapter (demo accounts only).

## Repository baseline

Python G1 safety kernel (mode, SafeEV, risk) plus MQL5 Observe/Shadow/DEMO_AUTO.
Live remains source-locked. No profitability claim.

## Capability map

| Capability | Evidence | State |
|---|---|---|
| Git | GitHub `firyomaefx/synthetic-indices` | Available |
| Python G1 kernel | `src/break100` + pytest | Implemented |
| Offline walk-forward | `src/break100/research/walkforward.py` | Unique-event rates only; no PnL GO |
| MQL5 EA | `BREAK100.mq5` v1.70 | Observe/Shadow/DEMO_AUTO |
| Capture | ticks, M1–H4, ARM setup, outcome | Pre-break setup; 1.65 cooldown |
| Box OCO | virtual stops; demo `OrderSend` if DEMO+demo account | Real account refused |
| Mode | DEMO requires `ACCOUNT_TRADE_MODE_DEMO`; LIVE always `LIVE_DISABLED` | Live NO-GO |
| Signal JSON | `BREAK100_signal_<sym>.jsonl` | Written on BUY/SELL |
| DemoExec | `DemoExec.mqh` OrderSend, magic 100165, SL required | Runtime demo-only |
| ML/RL production | UCB + C trainer; no calibrated model registry | Not G3 GO |
| Walk-forward evidence pack | Absent after-cost OOS | NO-GO for live |

## Operating truth

- OBSERVE / SHADOW: no broker orders.
- DEMO_AUTO: `OrderSend` only when the connected account is **demo** and risk gate passes.
- Real account + InpMode=DEMO → forced OBSERVE (`DEMO_ACCOUNT_REQUIRED`).
- LIVE input → OBSERVE (`LIVE_DISABLED`).
- Policy id: `BOX_OCO_UCB_v1`. Not a trained neural net.
- Decision: **LIMITED GO** for Observe/capture/signals; **NO-GO** for live and for claiming ML edge.
