# BREAK100

M30 box-breakout expert for **BREAK100** (Boom-class synthetic) on MetaTrader 5.

**EA v2.33** · chart **M30 only** · EA sends **no orders at all** · order placement lives in `RES-SUP OCO.mq5`, which **is live-enabled (real money)** · **not a profit claim**

EA: `OBSERVE → SHADOW` (detection, drawing, Telegram, Shadow ledger — never an order).
Orders: `RES-SUP OCO.mq5`, launched by hand per snapshot. Demo freely; **live accounts enabled by default** since v1.01 (`DECISION_LOG` D-007).

---

## About

This repo is the BREAK100 system used on a **Windows desktop MT5** chart.

It does **not** fade a range. It waits for a **tight M30 pause** (a box), watches **both sides**, and trades the **break**. First fill cancels the other stop (OCO). After fill, the chart shows dotted **SL / ENTRY / TP1 / TP2 / TP3** lines with the price on each line.

**Telegram** (M30 chart only) sends WATCH / ENTRY / TP / SL as replies on that day's signal. A short emoji **status** goes out every 6 hours.

Since v2.33 the **EA itself places no orders on any account or mode** — it detects, draws, alerts and logs. Orders come only from `mql5/Scripts/RES-SUP OCO.mq5`, which you launch by hand. That script **will trade a real account** (owner-authorised, `DECISION_LOG` D-007); set `InpAllowLiveTrading = false` in its input dialog to make a live run a no-op.

ML/RL reads closed fills and can SKIP / BUY-only / SELL-only / both. That is a learning loop, not a proven edge.

---

## How a signal works

1. **Box** — last 4–8 M30 bars, height ≤ 25% of the last H4 candle. Default is **range then break** (`InpImpulseK = 0`).
2. **WATCH** — **OCO both sides**: BUY STOP above the box and SELL STOP below. RL does not drop a side.
3. **Fill** — M30 **closes** outside. **BUY fill cancels SELL. SELL fill cancels BUY.**
4. **Path** — SL past the opposite rail. **TP1 = 1R (same as SL)**. TP2/TP3 from ML/RL (≥2R / ≥TP2). Dotted lines until TP3 / SL / time-exit.
5. **Log** — ticks, bars, and quality-gated `train.csv` for Hugging Face / the local trainer.

Do **not** attach this EA on M1 / M5 / M15 if you want one Telegram stream.

---

## Modes

| Mode | What happens |
|---|---|
| **OBSERVE** | Draw the box, send Telegram, log data. No broker orders. |
| **SHADOW** | Same, plus a virtual fill/close ledger. |
| *(orders)* | Not the EA's job any more — run `mql5/Scripts/RES-SUP OCO.mq5`. |
| **DEMO_AUTO / LIVE** | Selectable, but since v2.33 the EA no longer places orders in any mode. The inputs remain for the mode/health machinery the HUD and Shadow ledger read. |

---

## Attach (Windows MT5)

Desktop MT5 only. Not the iPhone app.

1. From the repo's `mql5\` folder on the Windows box, one command pulls, copies, and compiles the EA and the script into every MT5 terminal it finds:
   ```powershell
   .\Install-Break100-Box-Trading.ps1 -Pull -SyncHF
   ```
   (`-Pull` and `-SyncHF` are both optional — see the script's own header comment. Its compile step uses the MetaEditor CLI, so **F7 is not required by hand** unless you'd rather do it manually. Everything ships on `master`; add `-Branch master` if your checkout has drifted. The installer prints the versions it read off disk — expect **EA 2.33, Script 1.01** — and refuses to run if the OCO script is missing, rather than silently deploying an older build.)
2. Open **BREAK100, M30**. Attach **Break100 Box Trading** (Experts) — detection, HUD, Telegram, Shadow ledger. Inputs: strategy **BOX_M30**, mode **OBSERVE** (or SHADOW).
3. Experts log should show `B100 Telegram ON  chart=M30`. Other timeframes log `Telegram OFF`.

Step-by-step: [mql5/START_HERE.txt](mql5/START_HERE.txt) · [mql5/INSTALL.txt](mql5/INSTALL.txt)

**To actually place orders**, drag `RES-SUP OCO` (Scripts) onto the chart whenever you see a RES/SUP snapshot you want to act on. It's opt-in and manual — one launch per snapshot. See its own header comment for inputs and a demo-account test procedure.

> **This script trades real money.** Since v1.01 `InpAllowLiveTrading` defaults to `true` and there is no account allowlist, so on a live account it places live orders (owner-authorised, `DECISION_LOG` D-007). Set it to `false` in the input dialog to make a live run a no-op. Note the strategy has **no measured edge** — see [Honest limits](#honest-limits) and `research/BACKTEST_RESULTS.md`.

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

## Hugging Face (free tier only)

Private dataset [`Tengkolok/break100-boom`](https://huggingface.co/datasets/Tengkolok/break100-boom) (404 if you are logged out — that is expected).

| Role | Free how |
|---|---|
| Source of truth | Unique `quality=1` train + `policy.csv` the EA loads |
| Extra backup | Outcome CSV (fills). **No ticks, no tokens** |
| Dataset card | README on the Hub after sync |
| Click-to-train | CPU Space in `tools/hf_space` (no GPU — that was the old 402) |
| Always-on | 15-min **PC** task (free Spaces sleep) |

HF trains **SL/TP**. It does **not** drop an OCO side. Need **16+** unique `quality=1` rows. Not a profit claim.

Config (not in git): `Common\Files\BREAK100_hf.txt` (`token=` `dataset=Tengkolok/break100-boom`).

```powershell
python tools/break100_hf_train.py
python tools/break100_hf_sync.py
```

15-minute task: `tools/Install-BREAK100-HF-Sync.ps1`.

---

## Repo layout

| Path | What |
|---|---|
| `mql5/Experts/Break100 Box Trading.mq5` | Chart EA (v2.33) — detects boxes, draws RES/SUP, HUD/Telegram/Shadow ledger. Places no orders since v2.33. |
| `mql5/Scripts/RES-SUP OCO.mq5` | Standalone (v1.01): places the BUY STOP + SELL STOP pair off the chart's RES/SUP, cancels the sibling on fill. Run manually per snapshot. **Live accounts enabled** — real money. |
| `mql5/Install-Break100-Box-Trading.ps1` | One command: `-Pull` (git pull), copy EA + script + Include into every MT5 terminal found, compile both via the MetaEditor CLI, `-SyncHF` (HF sync). Everything except dragging the compiled files onto a chart. |
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
| **2.33** | OCO placement moved out of the EA into a standalone script, `mql5/Scripts/RES-SUP OCO.mq5` — it reads the EA's own RES/SUP rails, places BUY STOP + SELL STOP with SL/TP already attached, and cancels the sibling on fill by polling (a Script has no `OnTradeTransaction`). The EA still detects, gates, draws RES/SUP, and logs to the Shadow ledger, but no longer calls `OrderSend` for the box path — running the EA and the script together can no longer double-place an order. |
| **2.32** | Fixed `B100ArmBoxOco`: an unbraced `if` had made its `return` unconditional since v2.23, so OCO placement (and 4 sites of the same shape below it) never actually ran in any mode. Bar catch-up after a stall walked newest-first and dropped every older bar in the gap; fixed to oldest-first. HUD rows with no content painted the terminal's default "Label" caption instead of nothing — fixed, plus reworded wording (`orders ON/OFF`, box-floor multiple, untrained-model state). |
| **2.24–2.31** | Two-leg OCO (runner to TP3); manual trades and one-click entry logged to the shadow ledger; LIVE-init bug fixed (real-account check was silently forcing OBSERVE after the gate already passed); Telegram audit (duplicate alerts, runner-blind cancels, orphaned-pending fix, stale self-test version); history-box repaint fixed; on-chart dashboard mirrors the Telegram alert. |
| **2.23** | Shadow ledger runs in every mode for every box, filtered or not, tagged with the execution decision; capture CSVs versioned to v2 with a header matching the rows. |
| **2.22** | Box-size trade filter (`InpMinBoxSpreads`); stop re-anchored to the actual fill after a gapped entry; broker `trade_stops_level` honoured. |
| **2.21** | Gated LIVE toggle: input + real account + login allowlist + chart button, disarmed on every restart. |
| **2.20** | Renamed to Break100 Box Trading. Independent MFE/MAE labelling; learned direction gate applies to orders only. |
| **2.19** | Tick fill for ENTRY (no wait for M30 close). Late path: one TP message (furthest), not TP1+TP2+TP3 spam. Box paint unchanged from 2.15. |
| **2.15** | HF unique train file; outcome one row per box. **v2.16–2.18 reverted** (label experiments hid the box). |
| **2.14** | Armed auto box shows WATCH arrows on both stops (not a fill). Mint/magenta fill arrow + Alert only on M30 close outside. |
| **2.13** | HUD rows measured (WAIT then HUMAN never overlap). Drawn boxes snap to M30 wick high/low. Arrows half size (Wingdings 8pt). |
| **2.12** | Wick snap on harvest; journal width 1 |
| **2.11** | HUD: WAIT and HUMAN n on separate rows (no overlap) |
| **2.10** | TP1 always 1R; TP2/TP3 ML/RL; human-box UP/DN merged into unique train |
| **2.09** | After your rectangle, label the next M30 close as UP/DN (the big move) |
| **2.08** | `saved` tag + HUD HUMAN n when a rectangle is harvested |
| **2.07** | Harvest your MT5 rectangles as human box labels (`BREAK100_human_box_*.csv` → HF) |
| **2.06** | BUY/SELL journal arrows half size on M30 |
| **2.05** | Blotter-first: quality ignores ATR; unique train only; Telegram unique n; policy gate always OCO BOTH. Kill: 8 weeks unique n<16 or OOS R≤0 → no promotion |
| **2.04** | Core OCO: always both stops. BUY fill cancels SELL, SELL fill cancels BUY. RL SL/TP only |
| **2.03** | CAPA: chart always both sides + magenta SELL arrows. RL gate no longer zeros `sell_stop` on Observe |
| **2.02** | Hide dotted SL/TP rays when the path ends (TP3 / SL / time-exit), not only on the next WATCH |
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
- Unique `quality=1` rows are the book. **Kill after 8 weeks** if unique n < 16 or OOS R after spread ≤ 0: stay Observe, no TF change, no Live.
- Trainer never uses `learn.csv` copies. Policy direction is **OCO BOTH**.
- Web Grok and laptop Grok only meet through this GitHub remote. See [INTEGRATION.md](INTEGRATION.md).
