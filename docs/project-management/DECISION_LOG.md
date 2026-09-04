# Decision Log

| ID | Date | Decision | Rationale | Status |
|---|---|---|---|---|
| D-001 | 2026-08-13 | Use explicit evidence-gated operating modes | Prevent source availability from implying operating approval | Accepted |
| D-002 | 2026-08-13 | Keep execution adapters structurally separate | Observe/Shadow must not import or call broker execution | Accepted |
| D-003 | 2026-08-13 | Start with deterministic breakout policy | Simpler, auditable baseline precedes ML/RL complexity | Accepted |
| D-004 | 2026-08-13 | Use offline RL only and make it a challenger | No real-money exploration; deterministic baseline remains benchmark | Accepted |
| D-005 | 2026-08-13 | Treat absent data/evidence as `NO-GO` | Profitability and external execution cannot be inferred | Accepted |
| D-006 | 2026-09-03 | Move order placement out of the EA into a manually-run script | Detection and execution separate cleanly: the EA can run continuously as a detector/logger while orders require a deliberate human launch. Also removes any chance of the EA and the script both placing an order for the same box. | Accepted |
| D-007 | 2026-09-04 | Enable live/real accounts in `RES-SUP OCO.mq5` by default, with no account-number allowlist | **Owner instruction, explicit** ("fully enable at scripts for real account. I allow it"). This weakens the fail-closed default that D-001/D-005 established, and is recorded here because `CONTEXT.md` requires owner authority plus a recorded decision to do so. The owner was shown, at the time of the decision, that `research/BACKTEST_RESULTS.md` measures the strategy at -4.90% ROI / -0.164R expectancy with a best-of-20 t=+0.12 against the ~2.45 bar, and that the code was not compile-verified. Residual guard: a Script only runs on deliberate launch, its input dialog shows `InpAllowLiveTrading` every time, and a live run prints the account number and lot size before sending. | Accepted |

