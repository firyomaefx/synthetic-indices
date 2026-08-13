# Milestone and Gate Plan

| Gate | Required exit evidence | Current state |
|---|---|---|
| G0 Initiation | Audit, integration map, blockers, zero accidental order path | PASS on empty baseline; report recorded |
| G1 Planning | Architecture, schemas, RTM, risks, tests, no high design issue | IN PROGRESS |
| G2 Build | Clean builds, automated tests, deterministic replay, structural Observe/Shadow order isolation | NOT STARTED |
| G3 Validation | Leakage-safe, cost-aware OOS report and failure tests | BLOCKED: no data/model |
| G4 Demo | Verified Demo adapter, OrderCheck/reconciliation, genuine Demo evidence | BLOCKED: no Demo evidence |
| G5 Live Canary | Shadow/Demo thresholds, approved account, owner approval, valid lease | BLOCKED |
| G6 Handover | Final reports, runbooks, guide, versioned manifest | BLOCKED |

## Promotion policy

- Gates are monotonic only while their evidence remains valid.
- Expired approval, stale models, drift, reconciliation failures, or safety
  defects demote the system to a safer mode.
- G3 needs at least the stated data/event preferences or an explicit
  insufficient-evidence result.
- G4/G5 cannot be passed with simulated external evidence.

