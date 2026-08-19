# Current-State and Capability Report

## Repository baseline

Python G1 safety kernel (mode, SafeEV, risk) is present. MQL5 Observe/Shadow
package v1.41 is added under `mql5/`. There is still no broker order path.

## Capability map

| Capability | Evidence | State |
|---|---|---|
| Git version control | GitHub `firyomaefx/synthetic-indices` | Available |
| Python G1 kernel | `src/break100` mode / SafeEV / risk + tests | Implemented, fail-closed |
| MQL5 Observe EA | `mql5/Experts/BREAK100.mq5` v1.41 | Source ready; compile in MetaEditor (no `.ex5` in repo) |
| Channel indicator | `mql5/Indicators/BREAK100_Channel.mq5` | Visual only, no execution |
| Causal SL/TP learner | `mql5/Include/Break100/Learner.mqh` | UCB-1 + MFE/MAE quantiles, min 16 labels |
| Offline trainer | `tools/break100_trainer.c` | REINFORCE + walk-forward; Windows exe is a build artifact |
| Tick collection store | No durable tick warehouse | Absent |
| Statistical G2 edge pack | No walk-forward evidence pack | NO-GO |
| Deep ML/RL on ticks | Bandit/REINFORCE on labels only | Not G3 GO |
| Shadow/Demo/Live execution | Observe/Shadow only; Demo/Live rejected at init | NO-GO |
| Profitability evidence | Explicitly not claimed | Absent |

## Current operating truth

`OBSERVE` is the executable mode. The EA issues `NO_TRADE` and can print
hypothetical BUY/SELL with SL/TP1/2/3. Shadow is a virtual ledger only.
Demo, Live Canary, and Live remain `NO-GO`. Source code cannot enable Live.
