# Requirements Traceability Matrix

Status values: `PLANNED`, `IMPLEMENTED`, `VERIFIED`, `EXTERNAL_BLOCK`.

| ID | Requirement | Planned code | Planned verification | Status |
|---|---|---|---|---|
| SAF-01 | Live/AUTO defaults off | Python mode contract and MQL5 EA | state/config tests | IMPLEMENTED: Python contract |
| SAF-02 | Observe/Shadow cannot reach orders | separate execution adapters | static path + integration tests | IMPLEMENTED: Python import boundary |
| SAF-03 | Fail closed on uncertainty/fault | decision and health gates | fault-injection tests | IMPLEMENTED: mode fault path |
| SAF-04 | Owner approval, account allowlist, lease | live control service | expiry/identity/account tests | IMPLEMENTED: policy contract only |
| DAT-01 | Immutable UTC bid/ask ticks | data collector/store | schema, UTC, append-only tests | PLANNED |
| DAT-02 | Causal channels/features/labels | event pipeline | no-future-data and replay tests | PLANNED |
| STA-01 | Edge gateway and corrected tests | research module | IID negative control and reference tests | PLANNED |
| MOD-01 | Calibrated abstaining predictions | model pipeline | calibration/coverage/OOS tests | PLANNED |
| MOD-02 | Frozen versioned champion/rollback | model registry | checksum/schema/swap/rollback tests | PLANNED |
| EV-01 | After-cost SafeEV and NO_TRADE | decision engine | cost/tail/uncertainty unit tests | PLANNED |
| RL-01 | Offline conservative RL only | offline RL package | OOD/action and baseline comparison | PLANNED |
| RSK-01 | Stop-risk sizing and hard ceilings | risk engine | tick value/ceiling/drawdown tests | PLANNED |
| EXE-01 | Realistic Shadow fills | shadow simulator | deterministic and stress tests | PLANNED |
| EXE-02 | Demo verification and OrderCheck | Demo adapter | rejected/non-demo/reconcile tests | EXTERNAL_BLOCK |
| UI-01 | Minimal indicator with truthful state | MQL5 indicator | compile and visual checklist | PLANNED |
| AUD-01 | Immutable reasoned audit records | audit store | restart/corruption/redaction tests | PLANNED |
| VAL-01 | Purged walk-forward, costs and stress | validation pipeline | reproducible report | PLANNED |

Each `VERIFIED` transition must cite a command and immutable evidence artifact.
