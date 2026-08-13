# Project Context

## Project Summary
- Purpose: Build an evidence-gated BREAK100 research and MT5 trading system that fails closed when edge, safety, or approval evidence is insufficient.
- Main technologies: Planned Python 3, MQL5/MT5, ONNX, Parquet, and SQLite or DuckDB; project compatibility is not yet verified.
- Primary entry points: None implemented; architecture and PMP controls are under `docs/`.

## Current State
- Current version: Unreleased greenfield baseline.
- Working features: PMP and architecture documentation only; no trading system is running.
- Recent verified changes: Gate G0/G1 control artifacts created and validated on 2026-08-13.
- Known issues: No source, tests, datasets, models, Shadow/Demo evidence, approved account, or owner control lease.
- Pending work: Complete G1 executable contracts, then build the broker-independent safety kernel using TDD.

## Architecture
- Main components: Planned data, event, research, model, decision, risk, Shadow, isolated Demo/Live execution, MQL5 EA, and Indicator layers.
- Important directories: `docs/architecture`, `docs/project-management`, and `docs/security`; source/test directories are not yet created.
- Data flow: Planned tick to causal event to feature snapshot to frozen model to SafeEV and gates to mode adapter, ledger, audit, and reconciliation.
- External dependencies: Local Python 3.14.3 and two MetaEditor/MT5 installations are discovered but unverified; broker data and Demo access are absent.

## Constraints
- Compatibility requirements: Preserve causal UTC bid/ask processing and verify Python, ONNX, and MQL5 parity before promotion.
- Security requirements: AUTO/LIVE defaults off; Observe/Shadow cannot reach broker orders; owner approval, allowlists, and an expiring lease are mandatory for Live.
- Files or logic that must not be changed: Never weaken gate criteria, risk ceilings, evidence requirements, or fail-closed defaults without explicit owner authority and recorded decision.

## Loop History

### 2026-08-13 — Gate G0 Initiation Baseline
- Request: Begin the full BREAK100 adaptive AI/ML/RL MT5 project with Gate G0 and PMP controls before trading behaviour.
- Changes: Added project charter, scope, WBS, gates, RTM, RAID, quality/test/implementation plans, logs, architecture/data specifications, current-state report, order-path audit, and draft handover.
- Files affected: `README.md`, `CONTEXT.md`, and documentation under `docs/`.
- Validation: Required-artifact/H1 scan passed for 18 pre-context artifacts; secret-pattern scan passed; no source/order path exists.
- Result: G0 passed after artifact validation; G1 remains in progress; Shadow, Demo, Live Canary, and Live are NO-GO.
- Remaining work: Add executable mode/state contracts and structural non-trading dependency tests before any broker adapter.
