# Change Log

| Date | Change | Scope | Approval |
|---|---|---|---|
| 2026-08-23 | v2.05 Blotter-first: drop ATR from quality (TP3 was box_invalid); trainer unique quality=1 never learn.csv; policy gate BOTH; status unique n. 8-week kill. Live locked. | MQL5 Train + HF | Owner request |
| 2026-08-23 | HF free-tier: sync unique quality=1 train + outcome + dataset card; CPU Space only (no GPU/Pro). OCO sides unchanged. | tools/hf | Owner request |
| 2026-08-23 | v2.04 OCO core: always BUY STOP + SELL STOP. First fill cancels the other. RL must not drop a side before fill. Live locked. | MQL5 Box | Owner request |
| 2026-08-23 | v2.03 CAPA: only BUY arrows because HF gate SKIP/BUY zeroed sell_stop (p_dn≈0). Chart watches both; DEMO gate only; magenta 234 SELL arrows. Live locked. | MQL5 Box + arrows | Owner request |
| 2026-08-23 | v2.02 Hide dotted SL/ENTRY/TP rays when the path ends (TP3 / SL / horizon). Same signal leftover, not a new setup. Live locked. | MQL5 visual | Owner request |
| 2026-08-22 | GitHub README + About, START_HERE, INSTALL, INTEGRATION rewritten to match v2.01 (BREAK100 M30 box OCO, Telegram, HF, live locked). | docs | Owner request |
| 2026-08-22 | v2.01 6h Telegram status is a short emoji card (time, mode, last M30, n, gate, SL/TP). No HEALTHY/idle/legal footnote. Live locked. | MQL5 Telegram | Owner request |
| 2026-08-22 | v2.00 After stop fill: dotted horizontal rays + price text on each line (SL / ENTRY / TP1 / TP2 / TP3). Looks like Fib levels; not an OBJ_FIBO. Live locked. | MQL5 visual | Owner request |
| 2026-08-22 | v1.99 After BUY STOP / SELL STOP fill, chart draws a native MT5 Fibonacci object (dotted rays, price labels) for SL, ENTRY, TP1, TP2, TP3. Fill prices are latched so the lines survive box SCAN. Cleared on the next WATCH. Live locked. | MQL5 visual | Owner request |
| 2026-08-22 | v1.98 After BUY/SELL fill, chart shows dotted Fib-style lines with prices for ENTRY, SL, TP1, TP2, TP3 until path ends. Live locked. | MQL5 visual | Owner request |
| 2026-08-22 | v1.97 Journal arrows mint (BUY) / magenta (SELL), distinct from gold/red candles. Live locked. | MQL5 visual | Owner request |
| 2026-08-22 | v1.96 Range-then-break is default (WATCH the tight box; long M30 close is the fill). Impulse-before is logged, not required (`InpImpulseK=0`). Unique M30 data: ~52% impulses had a range immediately before. Live locked. | MQL5 Box | Owner request |
| 2026-08-22 | v1.95 Always-on capture: ticks/bars/account on every tick + OnTimer 60s heartbeat; file reopen wrap-safe; warehouse forced on while EA attached. Live locked. | MQL5 Capture | Owner request |
| 2026-08-22 | README.md brought to v1.94; release rule: every EA/tools change updates GitHub README in the same commit. | docs | Owner request |
| 2026-08-22 | v1.94 Telegram hard-lock: send only if chart is M30 and InpBoxTF is M30. Other TFs log OFF. Live locked. | MQL5 Telegram | Owner request |
| 2026-08-22 | v1.93 Telegram only from M30 chart; ENTRY/SL share g_levels; send-then-remember; reply-fail fallback; pts = price difference; faster WebRequest. Live locked. | MQL5 Telegram | Owner request |
| 2026-08-22 | v1.92 Impulse then range then break: box is the small pause after a long M30 (≥1.5× box height, real body). Impulse not inside the rectangle. ML logs imp_dir/size. Live locked. | MQL5 Box/Train/Capture | Owner request |
| 2026-08-22 | v1.91 Tight box: seed last 4 M30, add older only if they stay in-zone; height ≤ 25% of last 1 H4; max 8 bars; no infinite rays. Live locked. | MQL5 Box + paint | Owner request |
| 2026-08-22 | v1.90 Telegram daily Signal 1,2,… from 06:00 GMT; resets next 06:00. Same number on ENTRY/TP/SL replies. Live locked. | MQL5 Telegram | Owner request |
| 2026-08-22 | v1.89 Telegram: WATCH/ENTRY start a thread; TP1/TP2/TP3 reply on that message as soon as tagged; SL omitted if TP1 already posted. Tick-size points. Live locked. | MQL5 Telegram | Owner request |
| 2026-08-22 | v1.88 Adaptive M30 range: grow while bars belong to the same high/low (min 4 / max 24), nested in 3 H4 boxes; pattern features (touches, close loc, compress) for ML/RL. Break-only, no fade, no ATR. Live locked. | MQL5 Box/Train/Capture | Owner request |
| 2026-08-22 | v1.87 Box+RL without ATR decisions: pause nested in last 3 H4 boxes; fill on M30 close outside; SL beyond opposite rail in box heights; quality gate spread vs height. Live locked. | MQL5 Box/Train/EA | Owner request |
| 2026-08-21 | v1.86 Seamless HF sync: merge train by episode_id, retrain, push/pull policy both ways. 15-min task. Live locked. | tools/break100_hf_sync.py + EA kick file | Owner request |
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
