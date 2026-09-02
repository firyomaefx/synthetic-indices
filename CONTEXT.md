# Project Context

## Project Summary
- Purpose: Build an evidence-gated BREAK100 research and MT5 trading system that fails closed when edge, safety, or approval evidence is insufficient.
- Main technologies: Planned Python 3, MQL5/MT5, ONNX, Parquet, and SQLite or DuckDB; project compatibility is not yet verified.
- Primary entry points: `break100.nontrading.ModeController` is the first executable contract; architecture and PMP controls are under `docs/`.

## Current State
- Current version: MQL5 EA v2.23 (Observe/Shadow only); Python side adds an offline research package alongside the earlier safety kernel.
- Working features: PMP/architecture controls, broker-independent mode controller, after-cost SafeEV abstention, stop-risk sizing, hard loss/drawdown gates, the live BREAK100 Box Trading EA (Observe/Shadow/Demo_Auto, Live gated off), and an offline research package (`src/break100/research/`) that ports the MQL5 box detector to Python, replays fills tick-by-tick, and enforces chronological/trial-count-deflated significance testing.
- Recent verified changes: Full Python suite passed 91 tests on 2026-09-02 (up from 36), `mypy` now clean on 16 source files, `ruff` clean after an import-order autofix; MQL5 EA reached v2.23 (box-size trade filter, gapped-entry stop re-anchor, gated Live toggle, always-on Shadow ledger, v2 capture schema). A 20-configuration tick-level backtest over the full 41.2-day/3.56M-tick broker history found **no edge**: the shipped baseline nets −4.9% ROI (M30) with the measured 46.7% win rate matching the random-walk prediction from spread geometry (46.25%) almost exactly; the best of 20 variants reached t=+0.12, far short of the ~2.45 needed to clear the trial-count penalty. A quarantined v1 dataset (`research/quarantine/`) was found corrupted (MAE mirrored MFE, so it was never an independent measurement) and retired in favor of a `*_v2_*` schema.
- Known issues: No data/event/model pipeline, audit store, execution adapter, datasets, Shadow/Demo evidence, approved account, or owner control lease beyond the research findings above; broker history is capped at 41.2 days (1,979 M30 bars / 131 box events), well short of the ~2,000-event target, so any result is powered to detect only a large effect; a large batch of research/EA work is committed to disk but not yet staged/committed to git as of this entry.
- Pending work: Decide whether to keep collecting forward capture toward a usable M15-variant sample (~8.5 events/day) or pursue payoff-asymmetry research instead of direction prediction (direction is confirmed ~50/50 in every variant); complete G1 config/data/audit schemas; build the causal tick/event pipeline using TDD.

## Architecture
- Main components: Implemented non-trading mode, decision, and risk contracts; a live MQL5 EA (box detect/arm/fill, Shadow ledger, capture, Telegram, ML/RL learner); an offline research package (backtest, box detector port, bar-level replay, chronological holdout/significance testing, per-box policy, structure/tradeability battery, walk-forward metrics); planned data, event, model, isolated Demo/Live execution, and Indicator layers.
- Important directories: `src/break100/nontrading`, `src/break100/decision`, `src/break100/risk`, `src/break100/research`, `mql5/Experts`, `mql5/Include/Break100`, `tools`, `research` (backtest/data-ceiling findings, quarantined v1 data), `tests`, and `docs`.
- Data flow: Live path — MT5 ticks to `Box.mqh` detection to arm/fill/OCO to Shadow ledger and `train.csv` capture to HF sync/learner. Research path — exported tick/bar history (`tools/export_history.py`) to the ported box detector (`boxdetect.py`) to bar-level replay (`replay.py`) or tick-level backtest (`backtest.py`) to chronological holdout with trial-count-deflated significance (`holdout.py`). Planned: tick to causal event to feature snapshot to frozen model to SafeEV and gates to mode adapter, ledger, audit, and reconciliation.
- External dependencies: Local Python 3.14.3 and two MetaEditor/MT5 installations are discovered and now actively used (`tools/export_history.py`, `tools/screen_symbols.py` pull read-only from a running MT5 terminal via the MetaTrader5 Python bridge); broker retains only 41.2 days of BREAK100 history (a rolling window, not a one-time limit) so Demo access remains the gap for live evidence.

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

### 2026-08-14 — G1 Decision and Risk Safety Kernel
- Request: Enforce positive conservative after-cost expectancy and stop-risk sizing before any execution work.
- Changes: Added validated outcome/cost inputs, uncertainty-adjusted SafeEV, mandatory NO_TRADE, exact Decimal sizing, broker-minimum-anchored volume steps, configurable limits beneath hard ceilings, and loss/drawdown/position gates.
- Files affected: `src/break100/decision`, `src/break100/risk`, tests, behavioral spec, RTM, gate report, and change log.
- Validation: Wheel/compile checks passed during the work package; full `python -m pytest -q` passed 36 tests; line-length and diff checks passed; `ruff` and `mypy` remained unavailable.
- Result: Deterministic decision/risk contracts verified; no profitability or execution evidence exists; all modes beyond Observe remain NO-GO.
- Remaining work: Add versioned config, tick/event/audit schemas, causal replay, and statistical edge validation.

### 2026-09-02 — MQL5 EA to v2.23 and offline research package
- Request: Ship the live BREAK100 Box Trading EA through v2.15–2.23 (box-size filter, gapped-entry re-anchor, gated Live toggle, always-on Shadow ledger) and answer, with real broker history, whether the shipped strategy has after-cost edge.
- Changes: MQL5 EA/Include tree updated through v2.23 (see `docs/project-management/CHANGE_LOG.md`); added `src/break100/research/` (line-for-line Python port of the box detector, tick-level backtest engine, bar-level replay, chronological holdout with trial-count-deflated significance, per-box policy module replacing the collapsed HF logistic model, tradeability structure battery, walk-forward metrics) plus `tools/export_history.py`, `tools/screen_symbols.py`, `tools/backtest_break100.py`, and matching tests; quarantined a corrupted v1 dataset (`research/quarantine/`, MAE mirrored MFE) and moved to a `*_v2_*` capture schema.
- Files affected: `mql5/Experts/Break100 Box Trading.mq5`, `mql5/Include/Break100/*`, `src/break100/research/*`, `tools/*`, `tests/test_{boxdetect,holdout,policy,replay,structure}.py`, `research/BACKTEST_RESULTS.md`, `research/DATA_CEILING.md`, `research/quarantine/README.md`.
- Validation: `python -m pytest -q` passed 91 tests; `python -m mypy src` clean; `python -m ruff check` clean after an import-order autofix; 20-configuration backtest run against 3,559,792 ticks (41.2 days, complete 1 Hz record).
- Result: No statistically significant edge found in any of 20 tested configurations after trial-count correction (best t=+0.12 vs ~2.45 needed); the measured 46.7% win rate is explained entirely by spread geometry on a driftless walk, not by the strategy. Direction is confirmed ~50/50, so edge — if any exists — must come from payoff asymmetry, not direction prediction. All modes beyond Observe/Shadow remain NO-GO; this is a research finding, not a go/no-go gate change.
- Remaining work: This large change set is on disk and passing tests but not yet staged/committed to git. Decide research direction (forward-capture toward the M15 variant vs. payoff-asymmetry analysis) before further backtest iteration.
