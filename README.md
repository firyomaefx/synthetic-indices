# BREAK100 Adaptive Trading System

Safety-first research and execution platform for BREAK100 channel-touch,
bounce, and breakout events.

The repository is being built through evidence-gated modes:

`OBSERVE -> SHADOW -> DEMO -> LIVE_CANARY -> LIVE`

AUTO/LIVE trading is unavailable by default. No profitability or readiness
claim is valid without the gate evidence defined in
`docs/project-management/MILESTONE_GATE_PLAN.md`.

## Current status

- Gate G0: repository baseline audited; see the phase-gate report.
- Gate G1: architecture plus the broker-independent mode contract are established;
  remaining executable interfaces are still being planned.
- Operating mode: the controller defaults to `OBSERVE`; no order-submission code exists.
- Gate decision: `NO-GO` for Demo, Live Canary, and Live.

## Documentation

- `docs/architecture/ARCHITECTURE.md`
- `docs/architecture/DATA_AND_MODEL_SPEC.md`
- `docs/project-management/PROJECT_CHARTER.md`
- `docs/project-management/IMPLEMENTATION_PLAN.md`
- `docs/project-management/REQUIREMENTS_TRACEABILITY_MATRIX.md`
- `docs/project-management/PHASE_GATE_REPORTS.md`

## Local verification

```powershell
python -m pytest -q
python -m compileall -q src tests
python -m pip wheel . --no-deps --no-build-isolation --wheel-dir <temporary-directory>
```

`ruff` and `mypy` are specified as development dependencies but were not
available for the first executable validation run.
