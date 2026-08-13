# Project Charter

## Purpose

Build a local-first BREAK100 research and MT5 execution system that promotes
only statistically defensible, after-cost models through Observe, Shadow,
Demo, Live Canary, and Live gates.

## Objectives

- Model boundary attempts as causal competing-risk events.
- Produce calibrated probabilities, uncertainty, SafeEV, and `NO_TRADE`.
- Isolate Observe and Shadow from every broker-order API.
- Provide a complete, default-off execution path with owner-gated activation.
- Preserve reproducible data, model, decision, execution, and gate evidence.
- Restrict all future broker integration to Mtrading.

## Success criteria

- Source builds and automated tests pass at the claimed gate.
- Walk-forward evaluation is leakage-safe and includes realised or defensible
  conservative costs.
- Promotion criteria in the gate plan are met with recorded evidence.
- Any missing evidence produces a fail-closed `NO-GO`, not an inferred pass.

## Stakeholders and authority

- Owner: approves product decisions, approved accounts, and time-limited live
  control leases.
- Project/engineering: implements, tests, documents, and recommends gates.
- Model risk reviewer: verifies leakage, calibration, costs, and tail risk.
- Operator: runs Observe, Shadow, and approved Demo workflows.

No engineering artifact can substitute for explicit owner approval.

## Constraints

- No martingale, grid, averaging down, recovery sizing, or hidden leverage.
- Offline RL only; no exploratory RL may reach Demo or Live execution.
- Live models are frozen, versioned, checksummed, and explicitly approved.
- Secrets and full account credentials must not enter source or logs.

## Initial decision

Proceed with Gate G0/G1 foundation. Demo and all Live modes are `NO-GO`
until their evidence gates pass.
