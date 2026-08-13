# Decision Log

| ID | Date | Decision | Rationale | Status |
|---|---|---|---|---|
| D-001 | 2026-08-13 | Use explicit evidence-gated operating modes | Prevent source availability from implying operating approval | Accepted |
| D-002 | 2026-08-13 | Keep execution adapters structurally separate | Observe/Shadow must not import or call broker execution | Accepted |
| D-003 | 2026-08-13 | Start with deterministic breakout policy | Simpler, auditable baseline precedes ML/RL complexity | Accepted |
| D-004 | 2026-08-13 | Use offline RL only and make it a challenger | No real-money exploration; deterministic baseline remains benchmark | Accepted |
| D-005 | 2026-08-13 | Treat absent data/evidence as `NO-GO` | Profitability and external execution cannot be inferred | Accepted |

