# Project Context

## Project Summary
- Purpose: Build an evidence-gated BREAK100 research and MT5 trading system that fails closed when edge, safety, or approval evidence is insufficient.
- Main technologies: Planned Python 3, MQL5/MT5 for Mtrading, ONNX, Parquet, and SQLite or DuckDB; project compatibility is not yet verified.
- Primary entry points: `break100.nontrading.ModeController` is the first executable contract; architecture and PMP controls are under `docs/`.

## Current State
- Current version: Unreleased greenfield baseline.
- Working features: PMP/architecture controls, Mtrading-only broker policy, broker-independent mode controller, after-cost SafeEV abstention, stop-risk sizing, and hard loss/drawdown gates; no trading system is running.
- Recent verified changes: Mtrading identity and account/symbol allowlist policy added; full Python suite passed 43 tests on 2026-08-14.
- Known issues: No Mtrading data/event/model pipeline, audit store, execution adapter, MQL5 source, datasets, Shadow/Demo evidence, approved account, or owner control lease; `ruff` and `mypy` were unavailable.
- Pending work: Complete G1 config/data/audit schemas, then build the causal tick/event pipeline using TDD.

## Architecture
- Main components: Implemented non-trading mode, decision, and risk contracts; planned data, event, research, model, Shadow, isolated Demo/Live execution, MQL5 EA, and Indicator layers.
- Important directories: `src/break100/nontrading`, `src/break100/decision`, `src/break100/risk`, `tests`, and `docs`.
- Data flow: Planned tick to causal event to feature snapshot to frozen model to SafeEV and gates to mode adapter, ledger, audit, and reconciliation.
- External dependencies: Local Python 3.14.3 and Mtrading MetaEditor/MT5 are discovered but unverified; Mtrading data and Demo access are absent.

## Constraints
- Compatibility requirements: Preserve causal UTC bid/ask processing and verify Python, ONNX, and MQL5 parity before promotion.
- Security requirements: AUTO/LIVE defaults off; Observe/Shadow cannot reach broker orders; Mtrading identity, owner approval, allowlists, and an expiring lease are mandatory for Live.
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

### 2026-08-14 — G1 Decision and Risk Safety Kernel
- Request: Enforce positive conservative after-cost expectancy and stop-risk sizing before any execution work.
- Changes: Added validated outcome/cost inputs, uncertainty-adjusted SafeEV, mandatory NO_TRADE, exact Decimal sizing, broker-minimum-anchored volume steps, configurable limits beneath hard ceilings, and loss/drawdown/position gates.
- Files affected: `src/break100/decision`, `src/break100/risk`, tests, behavioral spec, RTM, gate report, and change log.
- Validation: Wheel/compile checks passed during the work package; full `python -m pytest -q` passed 36 tests; line-length and diff checks passed; `ruff` and `mypy` remained unavailable.
- Result: Deterministic decision/risk contracts verified; no profitability or execution evidence exists; all modes beyond Observe remain NO-GO.
- Remaining work: Add versioned config, tick/event/audit schemas, causal replay, and statistical edge validation.

### 2026-08-14 — Mtrading-Only Broker Policy
- Request: Restrict the system to Mtrading and publish the project to GitHub.
- Changes: Added exact Mtrading identity enforcement and empty-by-default account/symbol allowlists; removed alternative-broker references from architecture and project artifacts.
- Files affected: `src/break100/broker`, Mtrading policy tests, and scope/security/project documentation.
- Validation: Focused policy tests passed 7 tests; full Python suite passed 43 tests; wheel/compile, production/docs Mtrading-only scan, secret scan, line-length, and diff checks passed; `ruff` and `mypy` were unavailable.
- Result: Mtrading-only policy contract verified; no terminal connection, execution adapter, or approved account exists; all modes beyond Observe remain NO-GO.
- Remaining work: Publish the verified local commits to a GitHub repository, then build Mtrading tick/event/audit schemas.
