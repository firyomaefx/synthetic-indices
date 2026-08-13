# Quality Management Plan

## Quality rules

- Every claim maps to fresh command output or an immutable evidence artifact.
- Determinism, causal timing, cost inclusion, safety isolation, and recovery are
  release-blocking qualities.
- Simulated evidence is labelled and never used to pass an external gate.
- Model metrics must include uncertainty, calibration, abstention, regimes,
  weeks, costs, and tail behaviour.

## Reviews

- Code: tests, static analysis, dependency and secret scans.
- Trading safety: order-path reachability, risk ceilings, lease and fail-closed
  review.
- Model risk: leakage, baselines, multiple testing, OOS stability and stress.
- Operations: restart, reconciliation, rollback and audit integrity.

## Defect policy

Critical safety, leakage, reconciliation, or secret defects block promotion.
High defects block their affected gate. Lower defects require an owner, due
gate, and documented acceptance or correction.

