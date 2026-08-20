# BREAK100 Adaptive Trading System

Safety-first Observe/Shadow platform for BREAK100 channel-touch, bounce, and
breakout events.

`OBSERVE -> SHADOW -> DEMO -> LIVE_CANARY -> LIVE`

AUTO/LIVE trading is unavailable. No profitability claim.

## Two Grok Builds, one repo

Web Grok Build (grok.com) and laptop Grok Build 1.0.5 (`C:\Users\User`) **do
not share a disk**. They combine through this GitHub remote.

Read **[INTEGRATION.md](INTEGRATION.md)** and paste
**[prompts/LAPTOP_GROK.md](prompts/LAPTOP_GROK.md)** into the laptop app.

## Layout

| Path | What |
|---|---|
| `src/break100/` | Python G1 mode / SafeEV / risk |
| `mql5/` | MT5 EA v1.42, indicator, includes, `Install-BREAK100.ps1` |
| `tools/break100_trainer.c` | Offline REINFORCE trainer source |
| `desk/` | TypeScript Observe kernel (same learner as the EA) |
| `tests/` | Python contract tests |

## Laptop (compile + attach)

Desktop MT5 must already be installed. iPhone app cannot attach a custom EA.

```powershell
git clone https://github.com/firyomaefx/synthetic-indices.git
cd synthetic-indices
# see INTEGRATION.md for the MQL5 pack + Install-BREAK100.ps1
```

Attach **BREAK100** to Boom 100 Index M1. AutoTrading **OFF**. Real account is
fine for ticks. `issued` stays `NO_TRADE`.

## Python checks

```powershell
python -m pytest -q
python -m compileall -q src tests
```
