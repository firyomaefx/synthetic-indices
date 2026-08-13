# Sequenced Implementation Plan

1. Foundation
   - Create portable Python package, tests, schemas, configuration policy, and
     evidence directories.
   - Implement mode/state contracts before any execution adapter.
2. Safety kernel
   - Add health gates, SafeEV, hard risk ceilings, immutable audit events, and
     structural order isolation using TDD.
3. Data and events
   - Add UTC bid/ask collection, immutable storage, causal channel/event/label
     pipeline, deterministic replay, and provenance manifests.
4. Statistical gateway
   - Add reference-tested edge tests, corrected multiple testing, competing
     hazard comparison, IID negative control, and `NO_EDGE` report.
5. ML and registry
   - Add baselines, calibrated boosted challenger, uncertainty/abstention,
     manifests, ONNX export/parity, champion/challenger and rollback.
6. Shadow system
   - Add realistic fill simulation, virtual ledger, drift/health monitoring,
     risk engine, and Shadow evidence reports.
7. MQL5 Observe/Shadow
   - Build indicator and EA against a non-trading interface; compile and run
     deterministic fixtures.
8. Demo adapter
   - Add isolated Demo-only adapter, `OrderCheck`, broker-state reconciliation,
     and failure recovery. Never accept a real account.
9. Locked Live adapter
   - Add owner-only approval, approved-account/symbol allowlist, expiring lease,
     canary cap, emergency stop, and rollback. Remain unavailable until G5.
10. Offline RL challenger
    - Train only on historical/Shadow/Demo episodes and reject unless it beats
      the deterministic baseline after costs and OOD penalties.

Each step is a separate verified work package. Do not start a later execution
mode merely because its source exists; the operating gate remains authoritative.

