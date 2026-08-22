# BREAK100

M30 box-breakout expert for **BREAK100** (Boom-class synthetic) on MetaTrader 5.

**EA v2.01** · chart **M30 only** · live orders **locked** · **not a profit claim**

`OBSERVE → SHADOW → DEMO_AUTO (demo account only) → LIVE (disabled in source)`

---

## About

This repo is the BREAK100 system used on a **Windows desktop MT5** chart.

It does **not** fade a range. It waits for a **tight M30 pause** (a box), watches **both sides**, and trades the **break**. First fill cancels the other stop (OCO). After fill, the chart shows dotted **SL / ENTRY / TP1 / TP2 / TP3** lines with the price on each line.

**Telegram** (M30 chart only) sends WATCH / ENTRY / TP / SL as replies on that day’s signal. A short emoji **status** goes out every 6 hours.

**Real** accounts are for ticks and capture. **DEMO_AUTO** may place pending stops on a **demo** login only. **LIVE is rejected** in the source. AutoTrading stays **OFF** on a real account.

ML/RL reads closed fills and can SKIP / BUY-only / SELL-only / both. That is a learning loop, not a proven edge.

---

## How a signal works

1. **Box** — last 4–8 M30 bars, height ≤ 25% of the last H4 candle. Default is **range then break** (`InpImpulseK = 0`).
2. **WATCH** — BUY STOP above the box, SELL STOP below. RL may drop one side or skip the pause.
3. **Fill** — M30 **closes** outside the box. The other stop is deleted.
4. **Path** — SL past the opposite rail. TP in **box heights**. Dotted price lines stay until the next WATCH.
5. **Log** — ticks, bars, and quality-gated `train.csv` for Hugging Face / the local trainer.

Do **not** attach this EA on M1 / M5 / M15 if you want one Telegram stream.

---

## Modes

| Mode | What happens |
|---|---|
| **OBSERVE** | Draw the box, send Telegram, log data. No broker orders. |
| **SHADOW** | Same, plus a virtual fill/close ledger. |
| **DEMO_AUTO** | Pending BUY STOP + SELL STOP on a **demo** account if risk gates pass. |
| **LIVE** | Forced off. Source will not send live orders. |

---

## Attach (Windows MT5)

Desktop MT5 only. Not the iPhone app.

1. Pull this repo (`git pull origin master` in `synthetic-indices`).
2. Copy `mql5/Experts/BREAK100.mq5` and `mql5/Include/Break100/*` into the terminal `MQL5` folder. Compile in MetaEditor (**F7**). Expect **0 errors**.
3. Open **BREAK100, M30**. Attach **BREAK100**. Inputs: strategy **BOX_M30**, mode **OBSERVE** (or SHADOW). AutoTrading **OFF** on real.
4. Experts log should show `B100 Telegram ON  chart=M30`. Other timeframes log `Telegram OFF`.

Step-by-step: [mql5/START_HERE.txt](mql5/START_HERE.txt) · [mql5/INSTALL.txt](mql5/INSTALL.txt)

---

## Telegram

**M30 only.** Daily counter **Signal 1, 2, …** resets at **06:00 GMT**. ENTRY / TP / SL **reply** on that signal. SL is skipped if TP1 already posted.

Config (never commit this file):

`%APPDATA%\MetaQuotes\Terminal\Common\Files\BREAK100_telegram.txt`

```
token=...
chat=...
```

Copy from [`mql5/BREAK100_telegram.txt.example`](mql5/BREAK100_telegram.txt.example).

MT5 → Tools → Options → Expert Advisors → allow `https://api.telegram.org`.

6h status looks like:

```
📊 05:34 GMT
👁 OBSERVE
✅ M30 05:00
🧠 400  🚫 SKIP  trap 61%
🎯 0.9R → 2.2  3.4  4.6
⏳ WAIT
```

`🚫 SKIP` means the learner is blocking OCO this pause (often a high trap rate). That is information, not an edge.

---

## Hugging Face (free tier)

Private dataset backup + PC retrain. Same `policy.csv` the EA already loads. Need **16+** `quality=1` rows. Gradio Space needs Pro — skipped.

Config (not in git): `Common\Files\BREAK100_hf.txt` (`token=` `dataset=`).

```powershell
python tools/break100_hf_train.py
python tools/break100_hf_sync.py
```

15-minute task: `tools/Install-BREAK100-HF-Sync.ps1`.

---

## Repo layout

| Path | What |
|---|---|
| `mql5/Experts/BREAK100.mq5` | Chart EA (v2.01) |
| `mql5/Include/Break100/` | Box, capture, train, Telegram, demo exec, learner |
| `tools/break100_hf_train.py` | Tabular trainer → `policy.csv` |
| `tools/break100_hf_sync.py` | Merge train/policy with the Hub |
| `src/break100/` | Python mode / SafeEV / risk contracts |
| `tests/` | Python contract tests |
| `docs/project-management/CHANGE_LOG.md` | Full version table |

```powershell
python -m pytest -q
python -m compileall -q src tests
```

---

## Versions

| Ver | Change |
|---|---|
| **2.01** | Short emoji 6h Telegram status |
| **2.00** | After fill: dotted SL / ENTRY / TP1–3 rays with price on the line (not a Fib object) |
| **1.97** | BUY mint / SELL magenta arrows (not candle colours) |
| **1.96** | Range-then-break default; impulse-then-range is a tag |
| **1.95** | Warehouse always on (ticks + M1–H4 + account) |
| **1.94** | Telegram from the M30 chart only |
| **1.90** | Daily Signal 1, 2, … from 06:00 GMT |
| **1.80** | M30 OCO: WATCH both stops |

Every EA or tools change updates this README in the same commit.

---

## Honest limits

- No live `OrderSend` path. Do not “just enable” Live.
- Tokens for Telegram and Hugging Face stay in **Common Files**, never in git.
- Quality train rows are still thin. Policy `gate=SKIP` is common. That is **not** a go for money.
- Web Grok and laptop Grok only meet through this GitHub remote. See [INTEGRATION.md](INTEGRATION.md).
