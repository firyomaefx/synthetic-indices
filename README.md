# BREAK100

MQL5 Observe/Shadow EA for **BREAK100** (Boom-class synthetic) on **M30**.

Current EA: **v1.95**. Live orders **source-locked**. **No profit claim.**

`OBSERVE → SHADOW → DEMO_AUTO (demo account only) → LIVE (disabled)`

## What it does

1. Wait for a **long M30 candle** (impulse).
2. Draw a **small range** after it (4–8 overlapping M30 bars, height ≤ 25% of last 1 H4). The impulse is **not** inside the box.
3. **WATCH** both sides. **Fill** only if M30 **closes** outside the box. First fill cancels the other (OCO).
4. SL beyond the opposite rail, TP in **box heights**. ML/RL (UCB) sizes SL/TP from unique quality episodes; direction gate SKIP / BUY-only / SELL-only / OCO.

Telegram (M30 chart only): daily **Signal 1, 2, …** from **06:00 GMT**; ENTRY/TP/SL **reply** on that signal. SL skipped if TP1 already posted.

## Attach (laptop MT5)

Desktop MT5 only. Not the iPhone app.

1. `git pull origin master` in `synthetic-indices`.
2. Copy `mql5/Experts/BREAK100.mq5` and `mql5/Include/Break100/*` into the terminal `MQL5` folder (or run MetaEditor compile).
3. Attach **BREAK100** on **BREAK100 M30** only. AutoTrading **OFF** on a real account.
4. Experts log must show `B100 Telegram ON  chart=M30`. Other TFs: `Telegram OFF`.

Do **not** run the EA on M1/M5/M15 if you want a single Telegram stream.

Real account is for **ticks and capture**. `DEMO_AUTO` requires a **demo** login. LIVE is rejected in source.

## Telegram

Config (not in git): `%APPDATA%\MetaQuotes\Terminal\Common\Files\BREAK100_telegram.txt`

```
token=...
chat=...
```

MT5 → Tools → Options → Expert Advisors → allow `https://api.telegram.org`.

## Hugging Face (free tier)

Private dataset backup + PC retrain. Gradio Space needs Pro — skipped.

Config (not in git): `Common\Files\BREAK100_hf.txt` (`token=` `dataset=`).

```powershell
python tools/break100_hf_train.py
python tools/break100_hf_sync.py
```

15-min task: `tools/Install-BREAK100-HF-Sync.ps1`. Need **16+** `quality=1` rows in `BREAK100_train_*.csv`.

## Layout

| Path | What |
|---|---|
| `mql5/Experts/BREAK100.mq5` | Chart EA (v1.95) |
| `mql5/Include/Break100/` | Box, Capture, Train, Telegram, DemoExec, Learner |
| `tools/break100_hf_train.py` | Tabular trainer → `policy.csv` |
| `tools/break100_hf_sync.py` | Merge train/policy with Hub |
| `src/break100/` | Python G1 mode / SafeEV / risk |
| `tests/` | Python contract tests |

## Python checks

```powershell
python -m pytest -q
python -m compileall -q src tests
```

## Recent EA versions

| Ver | Change |
|---|---|
| **1.95** | Warehouse always on: ticks + M1–H4 + account every tick and every 60s timer, even if health FAULT |
| **1.94** | Telegram **M30 chart only** |
| 1.93 | SL replies; same SL as tracker; honest pts; send-then-remember |
| 1.92 | Impulse then small range then break |
| 1.91 | Tight box (4–8 bars, 25% of 1 H4); no infinite rays |
| 1.90 | Daily Signal 1,2,… reset 06:00 GMT |
| 1.89 | TP1/2/3 reply on the original ENTRY |
| 1.86 | HF bidirectional train/policy sync |
| 1.80 | M30 OCO WATCH both stops |

Full table: [docs/project-management/CHANGE_LOG.md](docs/project-management/CHANGE_LOG.md).

## Release rule

**Every EA or tools change updates this README** (version badge at the top + Recent versions row). Same commit as the code.

Web Grok and laptop Grok do not share a disk — they combine through this GitHub remote. See [INTEGRATION.md](INTEGRATION.md).
