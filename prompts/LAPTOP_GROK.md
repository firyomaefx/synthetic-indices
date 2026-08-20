Clone or pull https://github.com/firyomaefx/synthetic-indices.git in this worktree (git pull).

BREAK100 v1.50 adds M30 box-breakout (no fade). Same EA.

Install on this Windows machine:
1. Copy mql5/Experts/BREAK100.mq5, mql5/Indicators/BREAK100_Channel.mq5, and ALL of mql5/Include/Break100/ (now includes Box.mqh) into every %APPDATA%\MetaQuotes\Terminal\<hash>\MQL5 matching folder.
2. Compile indicator then EA with metaeditor64.exe. 0 errors. Version 1.50.
3. Attach BREAK100 to Boom 100 Index M30 (or M1 — box still uses M30 closed bars).
4. Inputs: InpStrategy = B100_STRAT_BOX_M30. InpMode = OBSERVE. AutoTrading OFF.
5. Do not add OrderSend. Real account OK for ticks.

Hypothesis encoded: after a persisted M30 close outside the prior Donchian box, do not fade. SL is a failed-break back inside. TP1/2/3 = 1/2/3 × box height. issued stays NO_TRADE.

Tell me compile log and what SIGNAL shows.
