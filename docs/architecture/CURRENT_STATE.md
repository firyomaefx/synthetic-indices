# Current-State and Capability Report

## Repository baseline

As observed on 2026-08-13, the repository was an initialized Git worktree with
no commit and no project files. There was no source, configuration, dependency
manifest, test, documentation, dataset, model, database, or generated binary.

The PMP and architecture documents added after that observation are the first
project artifacts. They do not implement trading behaviour.

## Capability map

| Capability | Evidence | State |
|---|---|---|
| Git version control | Initialized local repository | Available, no baseline commit |
| Python toolchain | Python 3.14.3 discovered | Available, project compatibility untested |
| MQL5 build toolchain | Monaxa and Mtrading MetaEditor executables discovered | Available, compile untested |
| Tick collection and storage | No code/data | Absent |
| Channel/event/feature pipeline | No code/tests | Absent |
| Statistical/ML/RL pipeline | No code/models | Absent |
| Indicator and EA | No MQL5 source or `.ex5` | Absent |
| Shadow/Demo/Live execution | No code/evidence | Absent |
| Profitability evidence | No dataset or evaluation | Absent |

## Confirmed integration candidates

- Local Python research and operational services.
- Explicitly selected local MetaEditor and MT5 terminal installations.
- Local analytical and operational stores after dependency validation.
- Versioned ONNX exchange after Python/MQL5 parity validation.

These are candidates, not verified working integrations.

## Current operating truth

There is no running trading system and therefore no active operating mode.
`OBSERVE` is the first planned executable mode. Shadow, Demo, Live Canary, and
Live remain `NO-GO`.

