# Project Context

## Project Summary
- Purpose: Build an evidence-gated BREAK100 research and MT5 trading system that fails closed when edge, safety, or approval evidence is insufficient.
- Main technologies: Planned Python 3, MQL5/MT5, ONNX, Parquet, and SQLite or DuckDB; project compatibility is not yet verified.
- Primary entry points: `break100.nontrading.ModeController` is the first executable contract; architecture and PMP controls are under `docs/`.

## Current State
- Current version: Unreleased greenfield baseline.
- Working features: PMP/architecture controls and a broker-independent operating-mode controller; no trading system is running.
- Recent verified changes: Mode promotions, Demo/Live control checks, lease expiry, fault demotion, and non-trading import boundaries passed 13 tests on 2026-08-13.
- Known issues: No data/event/model/decision/risk pipeline, execution adapter, MQL5 source, datasets, Shadow/Demo evidence, approved account, or owner control lease; `ruff` and `mypy` were unavailable.
- Pending work: Complete G1 schemas/interfaces, then extend the broker-independent safety kernel using TDD.

## Architecture
- Main components: Planned data, event, research, model, decision, risk, Shadow, isolated Demo/Live execution, MQL5 EA, and Indicator layers.
- Important directories: `src/break100/nontrading`, `tests`, `docs/architecture`, `docs/project-management`, and `docs/security`.
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

### 2026-08-13 — G1 Broker-Independent Mode Contract
- Request: Begin executable safety scaffolding without adding a broker-order path.
- Changes: Added Python packaging, explicit operating/account/system states, sequential gate promotion, Demo and Live control checks, continuous lease expiry, fail-closed fault handling, and AST dependency-boundary tests.
- Files affected: `pyproject.toml`, `.gitignore`, `.agents/specs`, `src/break100/nontrading`, `tests`, and relevant project-control documents.
- Validation: Wheel build and compile passed; `python -m pytest -q` passed 13 tests; line-length and diff checks passed; `ruff` and `mypy` skipped as unavailable.
- Result: Partial G1 safety contract verified; no order-submission source exists; all modes beyond Observe remain NO-GO.
- Remaining work: Define config/data/audit/risk interfaces and implement the decision/risk safety kernel before any execution adapter.
