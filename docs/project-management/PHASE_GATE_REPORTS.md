# Phase Gate Reports

## G0 Initiation — 2026-08-13

### Evidence

- Repository contained only `.git`; no commits, source, configuration, tests,
  documentation, datasets, models, or generated artifacts existed.
- Recursive file and keyword inventory found no MQL5 or Python broker-order
  call and therefore no accidental Live path.
- Observe/Shadow structural isolation is not yet implemented or proven; current
  unreachability results from the absence of all trading source.
- Local Python 3.14.3, Git, and two MetaEditor/MT5 installations were found;
  build/runtime compatibility is not yet proven.

### Integration points

- Python local research/runtime layer.
- MQL5 Indicator and EA compiled by an explicitly selected MetaEditor.
- Local Parquet plus SQLite/DuckDB storage, subject to dependency validation.
- ONNX bridge, subject to runtime/version parity validation.

### Blockers

- No BREAK100 historical bid/ask data, model, Shadow evidence, Demo evidence,
  approved account, or owner control lease.

### Decision

`PASS G0` after creation and validation of the initiation artifact set. Proceed
to G1 planning and safety-first scaffolding. `NO-GO` for Shadow, Demo, Live
Canary, and Live.

## G1 Planning — 2026-08-13

Status: `IN PROGRESS`. Architecture, data/model contracts, RTM, RAID, quality,
test, and implementation plans are recorded. A broker-independent Python mode
controller now defaults to Observe, enforces sequential evidence-gated
promotion, requires Demo/Live controls, checks lease expiry continuously, and
fails critical faults to Observe. AST-based tests verify its package cannot
import execution adapters or use order-submission symbols.

Validation evidence:

- Wheel build: passed for `break100-0.1.0-py3-none-any.whl`.
- Python compile: passed.
- Pytest: 13 passed.
- `ruff` and `mypy`: skipped because not installed in the current environment.

This is not a complete execution boundary because no execution adapter, MQL5
EA, or broker integration exists. G1 exit awaits the remaining interfaces and
schema contracts. Shadow, Demo, Live Canary, and Live remain `NO-GO`.

### 2026-08-14 safety-kernel evidence

- SafeEV validates probabilities, includes spread, commission and slippage,
  applies an uncertainty penalty, and abstains on unhealthy, non-positive, or
  ambiguous candidates.
- Position sizing derives volume from stop loss, tick size/value, and broker
  minimum/maximum/step metadata without rounding risk upward.
- Configurable values cannot exceed 0.25% per trade, 1% rolling 24-hour loss,
  3% weekly loss, 5% total drawdown, or one position per symbol.
- Full Python suite: 36 passed; compile and line-length checks passed.

This is mathematical/control evidence only. It is not profitability evidence,
does not validate broker metadata, and does not promote any operating mode.

### 2026-08-14 Mtrading-only scope evidence

- The broker policy accepts the exact reported identity `Mtrading` only.
- Empty account and symbol allowlists default to blocked.
- A non-Mtrading identity, unapproved account, or unapproved symbol fails
  closed with a stable reason code.
- Focused Mtrading policy test suite: 7 passed.

No terminal/account connection has been made, so this validates policy logic—not
Mtrading session identity, market data, order submission, or execution.
