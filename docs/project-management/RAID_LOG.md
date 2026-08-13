# RAID Log

## Risks

| ID | Severity | Risk | Response/owner | State |
|---|---|---|---|---|
| R-01 | Critical | Live order reachable before approval | Structural adapter isolation; default-deny lease and allowlists / engineering | Open |
| R-02 | Critical | Leakage or optimistic fills invent edge | Causal transforms, purged walk-forward, cost stress / model risk | Open |
| R-03 | High | Insufficient BREAK100 data | Remain Observe/Shadow; report insufficient evidence / owner | Open |
| R-04 | High | Synthetic-index regime/tail change | Drift, change-point, hard drawdown stops / model risk | Open |
| R-05 | High | MQL5/Python/ONNX mismatch | Versioned schemas, parity tests, checksum gate / engineering | Open |
| R-06 | High | Shadow simulator differs from broker | Demo calibration; block Live until tolerance met / engineering | Open |
| R-07 | Medium | Platform restart corrupts state | Atomic persistence, idempotent reconciliation / engineering | Open |

## Assumptions

| ID | Assumption | Validation |
|---|---|---|
| A-01 | Mtrading exposes BREAK100 bid/ask ticks and symbol metadata | Verify in an approved Mtrading MT5 session |
| A-02 | Owner will explicitly designate approved Demo/Live accounts | Owner-supplied evidence at G4/G5 |
| A-03 | Local Python and MetaEditor can support the planned build | Toolchain compile/probe during G2 |

## Issues

| ID | Severity | Issue | Required resolution |
|---|---|---|---|
| I-01 | High | No historical tick/event data exists in repository | Collect/import provenance-verified bid/ask data |
| I-02 | High | No genuine Shadow or Demo evidence exists | Accumulate the required time/trades after build |
| I-03 | Medium | Exact Mtrading symbol/account constraints are unverified | Read properties in approved Mtrading session |

## Dependencies

| ID | Dependency | Gate impact |
|---|---|---|
| D-01 | MT5 terminal and MetaEditor | MQL5 build/runtime evidence at G2+
| D-02 | Python analytical/ONNX packages | statistical/ML build at G2+
| D-03 | Genuine Mtrading Demo environment | G4/G5 external evidence
