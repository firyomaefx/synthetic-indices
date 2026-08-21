# Change Log

| Date | Change | Scope | Approval |
|---|---|---|---|
| 2026-08-21 | HF as always-on backup trainer: Space UI + Backup-BREAK100-HF.bat pushes train+policy to private dataset. Same policy.csv as EA. Live locked. | tools/hf_space | Owner request |
| 2026-08-21 | Hugging Face tabular trainer (datasets + sklearn) writes EA policy.csv; optional --push-hub. DistilBERT not default (n too small). Live locked. | tools/break100_hf_train.py | Owner request |
| 2026-08-21 | v1.85 Telegram self-test card on attach (WATCH/ENTRY/SL/TP preview). Live locked. | MQL5 Telegram | Owner request |
| 2026-08-21 | v1.84 Simple Telegram WATCH/ENTRY/SL HIT/TP HIT with emoji. Cross-chart dedup. SL/TP no longer 0.00. Live locked. | MQL5 Telegram | Owner request |
| 2026-08-21 | v1.83 Quality-gated BREAK100_train_*.csv: post-fill MFE/MAE path, spread/box filters, trainer prefers train over learn. Warehouse unchanged. Live locked. | MQL5 Train.mqh + trainer | Owner request |
| 2026-08-21 | v1.82 RL direction gate (SKIP/BUY-only/SELL-only/OCO) + SL/TP UCB/REINFORCE. Trains on closed labels. Live locked. DEMO_AUTO demo only. | MQL5 learner + trainer | Owner request |
| 2026-08-21 | v1.81 Telegram ML/RL status every 6 hours (capture, learner, box counts). Dedup across charts. Live remains locked. | MQL5 EA Telegram digest | Owner request |
| 2026-08-21 | v1.80 M30 box OCO: WATCH arms BUY STOP + SELL STOP; first fill deletes the other. Shadow simulates. DEMO_AUTO places broker pendings on demo accounts only. Telegram WATCH/FILL/CANCEL/CLOSE with SL/TP points. Live remains locked. | MQL5 EA + DemoExec pending + Telegram | Owner request |
| 2026-08-13 | Established Gate G0/G1 project-control baseline | Documentation only | Project charter authority |
| 2026-08-13 | Added broker-independent operating-mode contract and structural boundary tests | Python G1 safety foundation | Project charter authority |
| 2026-08-14 | Added SafeEV abstention, stop-risk sizing, and immutable risk ceilings | Python G1 safety kernel | Project charter authority |
| 2026-08-20 | Added Observe/Shadow MQL5 EA v1.41, visual channel indicator, causal UCB+quantile SL/TP learner, and offline Windows REINFORCE trainer. No OrderSend. Live/Demo remain NO-GO. | MQL5 Observe package + trainer source | Project charter authority |
