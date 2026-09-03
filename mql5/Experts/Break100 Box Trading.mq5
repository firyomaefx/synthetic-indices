#property copyright "Break100 Box Trading"
#property version   "2.32"
#property description "Break100 Box Trading — M30 box breakout with OCO rails."
#property description "2.32  fixed unreachable OCO placement; empty HUD rows no longer paint \"Label\""
#property description "2.31  fixed orphaned BUY runner pending when SELL leg1 placement fails"
#property description "2.30  Telegram audit: fixed dup TP/close alerts, runner-blind cancels, stale self-test ver"
#property description "2.29  fixed history-box repaint (n_boxes not hist_n); button/Label diagnostics"
#property description "2.28  fixed dashboard spacing bug that pushed LIVE/ENTER off-screen"
// Older history (2.27 and earlier) dropped from here: MetaEditor caps the
// combined length of all #property description lines around 500 chars and
// silently truncates or warns past it. Full history stays in CHANGE_LOG.md.

// Keep in step with #property version above. MQL5 exposes no macro for the
// property, so this duplicate is the only way to report the build at runtime —
// and the two drift apart the moment someone edits one and not the other.
#define B100_VERSION "2.32"

#include <Break100/Channel.mqh>
#include <Break100/Mode.mqh>
#include <Break100/SafeEV.mqh>
#include <Break100/Risk.mqh>
#include <Break100/Shadow.mqh>
#include <Break100/Learner.mqh>
#include <Break100/Box.mqh>
#include <Break100/Capture.mqh>
#include <Break100/Signal.mqh>
#include <Break100/DemoExec.mqh>
#include <Break100/Telegram.mqh>
#include <Break100/Train.mqh>

input ENUM_B100_MODE InpMode           = B100_OBSERVE; // OBSERVE/SHADOW/DEMO(demo). LIVE needs the gates below.
input bool           InpAllowLiveTrading = false;      // Gate 1: permit LIVE at all. Real money.
input long           InpLiveAccountLogin = 0;          // Gate 2: must equal this account's login exactly
input bool           InpShowLiveButton  = true;        // Gate 3: show the arm/disarm button on the chart
input ENUM_B100_STRAT InpStrategy      = B100_STRAT_BOX_M30; // CHANNEL tick band, or M30 box breakout

input ENUM_TIMEFRAMES InpBoxTF         = PERIOD_M30;   // Box timeframe
input int            InpBoxMinBars     = 4;            // Min M30 bars in the pause (2h)
input int            InpBoxMaxBars     = 8;            // Max M30 bars (one H4)
input int            InpBoxAtrPeriod   = 14;           // unused (kept for old .set files)
input double         InpBoxH4Frac      = 0.25;         // Box height ≤ this × last 1 H4 candle
input double         InpBoxWiden       = 0.10;         // Older bar may poke at most this × height
input double         InpImpulseK       = 0.0;          // 0 = do not require impulse (range-then-break). >0 = require long candle before box
input double         InpBoxSlBuf       = 0.15;         // SL beyond opposite rail, in box heights
input bool           InpTwoLegs        = true;         // Two legs per side: leg1 exits at TP1, runner rides to TP3
input double         InpLotsPerLeg     = 0.01;         // Fixed volume per leg (both legs), matches sibling OCO EA
input double         InpMinBoxSpreads  = 12.0;         // Min box height to TRADE, in spreads (0=off). Alerts unaffected.
input double         InpMaxEntryGapR   = 0.0;          // Reject fills gapping > this many R past the stop (0=off)
input int            InpBoxTimeout     = 10;           // Armed closes without fill → cancel
input bool           InpBoxNoFade      = true;         // Never fade the pause

input int            InpMadWindow      = 160;          // MAD window
input double         InpKalmanQ        = 0.08;         // Kalman Q
input double         InpKalmanRFloor   = 0.04;         // Kalman R floor
input double         InpMadK           = 2.4;          // MAD k
input int            InpPersistTicks   = 6;            // Persist ticks for breakout
input int            InpLabelHorizon   = 48;           // Label horizon ticks

input double         InpCostSpread     = 0.40;         // Cost: spread
input double         InpCostCommission = 0.15;         // Cost: commission
input double         InpCostSlippage   = 0.25;         // Cost: slippage
input double         InpUncertaintyK   = 1.4;          // Uncertainty k
input int            InpMinSamples     = 12;           // Min labels before edge

input double         InpRiskFraction   = 0.002;        // Risk fraction (capped 0.25%)
input double         InpStopAtrMult    = 1.0;          // SL distance = k * half-width
input double         InpTp1R           = 1.0;          // TP1 in R (1R = SL distance)
input double         InpTp2R           = 2.0;          // TP2 in R
input double         InpTp3R           = 3.0;          // TP3 in R

input bool           InpUseLearner     = true;         // Dynamic SL/TP + direction from closed labels
input bool           InpDirLearner     = true;         // Learned direction gate applies to orders only; both rails always alert
input int            InpTrainHorizon   = 12;           // M30 bars to measure MFE/MAE after fill
input bool           InpTrainLog       = true;         // Write BREAK100_train_*.csv (quality gated)
input bool           InpShadowLedger   = true;         // Virtual fills in SHADOW
input bool           InpDrawChannel    = true;         // Draw channel lines
input bool           InpAttachIndicator= true;         // Attach visual indicator
input bool           InpDrawArrows     = true;         // Arrows on buy/sell/exit
input bool           InpDrawLevels     = true;         // Draw entry/SL/TP lines
input bool           InpAlerts         = true;         // Popup on BUY/SELL/EXIT
input bool           InpCapture        = true;         // Always-on ticks + M1-H4 + account (forced while EA attached)
input bool           InpTelegram       = true;         // Telegram: M30 chart only (other TFs silent)
input int            InpStatusHours    = 6;            // ML/RL status to Telegram (0=off)
input bool           InpHarvestRects   = true;         // Save your drawn rectangles as human boxes

#define IND_SHORT  "BREAK100 Channel"
#define LINE_MID   "B100_centre"
#define LINE_UP    "B100_upper"
#define LINE_DN    "B100_lower"
#define LBL_SIG    "B100_signal"
#define LBL_LV     "B100_levels"
#define LBL_HUM    "B100_human"
#define LBL_MODE   "B100_lbl_mode"
#define LBL_BUY1   "B100_lbl_buy1"
#define LBL_BUY2   "B100_lbl_buy2"
#define LBL_SELL1  "B100_lbl_sell1"
#define LBL_SELL2  "B100_lbl_sell2"
#define LBL_BOXINFO "B100_lbl_boxinfo"
#define LBL_MODEL  "B100_lbl_model"
#define LV_ENTRY   "B100_lv_entry"
#define LV_SL      "B100_lv_sl"
#define LV_TP1     "B100_lv_tp1"
#define LV_TP2     "B100_lv_tp2"
#define LV_TP3     "B100_lv_tp3"
#define LV_ENTRY_L "B100_lv_entry_l"
#define LV_SL_L    "B100_lv_sl_l"
#define LV_TP1_L   "B100_lv_tp1_l"
#define LV_TP2_L   "B100_lv_tp2_l"
#define LV_TP3_L   "B100_lv_tp3_l"
#define LV_FIBO    "B100_fib"
#define BOX_RECT   "B100_box"
#define BOX_RES    "B100_box_res"
#define BOX_SUP    "B100_box_sup"
#define BOX_MID    "B100_box_mid"
#define BOX_BUY    "B100_box_buystop"
#define BOX_SELL   "B100_box_sellstop"
#define BOX_RES_LBL "B100_box_res_lbl"
#define BOX_SUP_LBL "B100_box_sup_lbl"
#define BOX_ARR_BUY "B100_box_arr_buy"
#define BOX_ARR_SELL "B100_box_arr_sell"
#define BOX_WATCH_L "B100_box_watch"
#define HUD_BG     "B100_hud_bg"
#define BTN_LIVE   "B100_btn_live"
#define BTN_ENTER  "B100_btn_enter"

#define CLR_INK      C'11,13,18'
#define CLR_HUD      C'16,18,24'
#define CLR_BOX_FILL C'245,245,250'
#define CLR_RES      C'198,162,98'
#define CLR_SUP      C'86,138,128'
#define CLR_EQ       C'120,118,108'
#define CLR_BUY      C'46,180,90'
#define CLR_SELL     C'214,64,64'
#define CLR_ARR_BUY  C'80,255,180'
#define CLR_ARR_SELL C'255,80,220'
#define B100_ARROW_FS 8

struct B100Levels
  {
   bool              valid;
   int               dir;
   double            entry;
   double            sl;
   double            tp1;
   double            tp2;
   double            tp3;
   double            r;
   int               tp_hit;   // 0,1,2,3
  };

struct B100Fib
  {
   bool              on;
   int               dir;
   datetime          t0;
   datetime          t1;
   double            entry;
   double            sl;
   double            tp1;
   double            tp2;
   double            tp3;
  };

B100Pipe        g_pipe;
B100Mode        g_mode;
B100ShadowBook  g_shadow;
B100Decision    g_decision;
B100Levels      g_levels;
B100Fib         g_fib;
B100Learner     g_learner;
B100LearnPolicy g_policy;
B100Box         g_box;
B100Capture     g_capture;
B100Episode     g_episode;
int             g_ind_handle = INVALID_HANDLE;
bool            g_ready      = false;
// Bottom edge of the HUD dashboard, in pixels from the chart's top-right
// corner. The dashboard's height varies with content (armed vs not, filled vs
// not), so LIVE/ENTER anchor to this instead of a fixed Y — a fixed Y is what
// let the dashboard grow tall enough to paint over the buttons and hide them.
int             g_dash_bottom_y = 100;
datetime        g_last_bar   = 0;
string          g_last_event = "";
string          g_init_note  = "";
string          g_risk_code  = "RISK_GATE_PASSED";
string          g_signal     = "WAIT";
string          g_signal_note= "warmup";
string          g_last_alert = "";
int             g_signal_seq = 0;
datetime        g_last_learn_bar = 0;
datetime        g_last_exec_bar  = 0;
ulong           g_oco_buy_tk     = 0;   // leg 1, exits at TP1
ulong           g_oco_sell_tk    = 0;
ulong           g_oco_buy_tk2    = 0;   // leg 2 (runner), rides to TP3
ulong           g_oco_sell_tk2   = 0;
// Runner bookkeeping. Positions are found by comment marker rather than ticket:
// tickets do not survive a terminal restart, POSITION_COMMENT does.
int             g_runner_stage   = 0;   // 0 none, 1 stop at breakeven, 2 stop at TP1
// Manual (magic 0) trade tracking. Entry is remembered so the closing deal can
// be written as one complete ledger row.
bool            g_manual_entry_override = false;
int             g_man_dir        = 0;
double          g_man_entry      = 0;
double          g_man_sl         = 0;
double          g_man_lots       = 0;
datetime        g_man_opened     = 0;
bool            g_oco_armed      = false;
string          g_oco_sid        = "";
double          g_oco_buy_px     = 0;
double          g_oco_sell_px    = 0;
double          g_oco_sl_buy     = 0;
double          g_oco_sl_sell    = 0;
double          g_oco_tp_buy     = 0;
double          g_oco_tp3_buy    = 0;   // runner target, carried into the alert
double          g_oco_tp3_sell   = 0;
double          g_oco_tp_sell    = 0;
double          g_oco_lots       = 0;
int             g_oco_fill_dir   = 0;
double          g_oco_fill_px    = 0;
datetime        g_oco_watch_bar  = 0;
datetime        g_oco_fill_bar   = 0;
datetime        g_oco_cancel_bar = 0;
long            g_tg_watch_id    = 0;
long            g_tg_entry_id    = 0;
int             g_tg_tp_announced = 0;
datetime        g_tg_thread_bar  = 0;
bool            g_skin_on    = false;
color           g_old_bg, g_old_fg, g_old_grid, g_old_up, g_old_dn, g_old_bull, g_old_bear, g_old_ask, g_old_bid, g_old_vol;
bool            g_old_show_grid, g_old_show_vol, g_old_show_ohlc, g_old_show_ask;
int             g_human_n    = 0;

void B100PaintBox();
void B100WatchGlyph(const string name, const datetime t, const double price,
                    const int code, const color clr, const ENUM_ANCHOR_POINT anc, const string tip);
void B100HideWatchMarks();
void B100PaintHud();
void B100HudLabel(const string name, const int x, const int y, const int fs,
                  const string font, const color clr, const string text);
void B100ApplyChartSkin();
void B100RestoreChartSkin();
void B100MarkBoxSignal(const int dir, const double price, datetime when = 0);
void B100ReplayJournalMarks();
void B100RescaleJournalMarks();
int  B100JournalWidth();
void B100HarvestHumanBoxes();
int  B100Pts(const double a, const double b);
string B100Px(const double x);
void B100FillSlTpFallback(const int dir, const double px, double &sl, double &tp1, double &tp2, double &tp3);
void B100FillBoxLevels(const int dir, const double entry, const double ask, const double bid);
void B100Tg(const string text);
void B100OcoClearTickets(void);
void B100ArmBoxOco(const double bid, const double ask);
void B100CancelBoxOco(const string reason);
void B100TelegramWatch(void);
void B100TelegramFill(const int dir, const double px, const bool sibling_deleted);
void B100FibLatch(const int dir, const double entry, const double sl, const double tp1, const double tp2, const double tp3);
void B100FibClear(void);
void B100TelegramCancel(const string reason);
void B100TelegramClose(const string why, const int dir, const double entry, const double exit_px, const double sl, const double tp, const double pts, const bool is_runner = false);
void B100TelegramTp(const int level, const double px);
void B100TgThreadSave(void);
void B100TgThreadLoad(void);
long B100TgParent(void);
datetime B100StatusReadGmt(void);
void     B100StatusWriteGmt(const datetime t);
void     B100MaybeStatus(void);
void     B100TelegramStatus(void);
void     B100TelegramSelfTest(void);
double   B100MoneyRisk(const double dist, const double lots);
void     B100ManageRunner(const double bid, const double ask);
void     B100ManualDeal(const ulong deal);
void     B100EnterButtonPaint(void);
void     B100LiveButtonCreate(void);
void     B100LiveButtonPaint(void);
bool     B100LiveGatesOk(string &why);
void     B100LogObjectDiagnostics(void);

int OnInit()
  {
   // Unmissable in the Experts tab, so the running build can always be
   // identified without opening the properties dialog.
   Print("========================================================");
   // MQL5 has __DATETIME__ (a datetime value) rather than C's __DATE__/__TIME__.
   Print("  Break100 Box Trading  v", B100_VERSION,
         "   compiled ", TimeToString(__DATETIME__, TIME_DATE | TIME_MINUTES));
   Print("  chart=", _Symbol, " ", EnumToString(Period()),
         "   account=", AccountInfoInteger(ACCOUNT_LOGIN),
         " (", (B100IsDemoAccount() ? "DEMO" : (B100IsRealAccount() ? "REAL" : "UNKNOWN")), ")");
   Print("========================================================");

   const bool live_account_ok = (InpLiveAccountLogin != 0 &&
                                 InpLiveAccountLogin == AccountInfoInteger(ACCOUNT_LOGIN));
   // B100ApplyRequestedMode is the single place mode is decided. It already
   // requires a real account for LIVE, and already forces OBSERVE on any of its
   // four gates failing (wrong account type, InpAllowLiveTrading off, unlisted
   // login). A second override used to run right here and stomp the *pass*
   // case back to OBSERVE whenever InpMode was DEMO or LIVE on a real account —
   // a leftover from v1.42-v1.61, before the LIVE gate existed, when the
   // account-type check was the only gate there was. It made LIVE structurally
   // unreachable on a real account regardless of the chart button: the button
   // could report ARMED while g_mode.mode had already been forced back to
   // OBSERVE here, so B100BrokerOrderIntentPermitted() always returned false.
   g_init_note = B100ApplyRequestedMode(g_mode, InpMode, InpAllowLiveTrading, live_account_ok);

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double mid = (bid > 0.0 && ask > 0.0) ? 0.5 * (bid + ask) : SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   B100PipeInit(g_pipe, mid, InpMadWindow, InpKalmanQ, InpKalmanRFloor, InpMadK,
                InpPersistTicks, InpLabelHorizon);
   B100ShadowInit(g_shadow);
   // Continue the shadow ledger across reattach/recompile instead of
   // silently restarting realised P&L and the trade count from zero.
   B100ShadowStateLoad(g_shadow);
   ZeroMemory(g_levels);
   ZeroMemory(g_fib);
   B100LearnerInit(g_learner);
   // Fit only on samples from the strategy actually running.
   g_learner.strat_filter = (int)InpStrategy;
   B100BoxInit(g_box);
   B100BoxScanHistory(g_box, InpBoxTF, InpBoxMinBars, InpBoxMaxBars, InpBoxAtrPeriod, InpBoxH4Frac, InpBoxWiden, InpImpulseK);
   B100CaptureInit(g_capture, true);
   B100TrainInit(g_episode);
   if(InpTelegram)
     {
      B100TelegramLoad();
      B100TgThreadLoad();
      if(B100TgChart())
        {
         Print("B100 Telegram ON  chart=M30  boxTF=M30");
         B100TelegramSelfTest();
        }
      else
         Print("B100 Telegram OFF  chart=", EnumToString(Period()),
               "  boxTF=", EnumToString(InpBoxTF), "  — alerts only on M30");
     }
   B100LearnerLoad(g_learner);
   if(B100PolicyLoad(g_policy))
     {
      g_learner.last_arm = g_policy.arm;
      Print("BREAK100 loaded offline policy  source=", g_policy.source,
            " n=", g_policy.n, " arm=", g_policy.arm_id,
            " gate=", g_policy.dir_gate,
            " SL=", DoubleToString(g_policy.sl_r, 3),
            " TP=", DoubleToString(g_policy.tp1_r, 2), "/",
            DoubleToString(g_policy.tp2_r, 2), "/", DoubleToString(g_policy.tp3_r, 2));
     }
   else
      B100LearnerPolicy(g_learner, 0, g_policy);
   g_decision.action       = B100_NO_TRADE;
   g_decision.reason       = "WARMUP";
   g_decision.hypothetical = B100_NO_TRADE;
   g_decision.hypo_reason  = "WARMUP";
   g_decision.safe_ev      = 0.0;
   g_signal                = "WAIT";
   g_signal_note           = "warmup — no buy/sell yet";

   if(InpAttachIndicator && InpStrategy == B100_STRAT_CHANNEL)
     {
      g_ind_handle = iCustom(_Symbol, PERIOD_CURRENT, "BREAK100_Channel",
                             InpMadWindow, InpKalmanQ, InpKalmanRFloor, InpMadK);
      if(g_ind_handle != INVALID_HANDLE)
         ChartIndicatorAdd(0, 0, g_ind_handle);
     }

   B100CreateLines();
   B100PaintHistBoxes();
   g_ready = true;

   Print("BREAK100 init  mode=", B100ModeName(g_mode.mode),
         "  health=", (g_mode.health == B100_HEALTHY ? "HEALTHY" : "FAULT"),
         "  oco=", (InpStrategy == B100_STRAT_BOX_M30 ? "M30_BOX" : "off"),
         "  account=", (B100IsDemoAccount() ? "DEMO" : (B100IsRealAccount() ? "REAL" : "UNKNOWN")),
         "  strat=", (InpStrategy == B100_STRAT_BOX_M30 ? "BOX_M30" : "CHANNEL"),
         "  telegram=", (g_tg_ok && InpTelegram ? "ON" : "OFF"),
         "  learner_n=", g_learner.n, "  policy=", g_policy.source);
   if(g_init_note != "")
      Print(g_init_note);
   B100ApplyChartSkin();
   if(InpStrategy == B100_STRAT_BOX_M30)
     {
      B100PaintBox();
      B100ReplayJournalMarks();
      B100RescaleJournalMarks();
     }
   // Dashboard first, so B100LiveButtonCreate() positions its buttons using a
   // real g_dash_bottom_y rather than the pre-paint placeholder.
   B100PaintPanel();
   B100LiveButtonCreate();
   // MT5's default OBJPROP_TEXT for a manually-inserted OBJ_LABEL is the
   // literal word "Label". Nothing in this file creates one — every
   // ObjectCreate(...,OBJ_LABEL,...) call site sets its text in the same
   // breath — so an object with that exact name is stray clutter from
   // outside the EA (a leftover manual insert, or another tool that ran on
   // this chart). Narrow exact-name match only; touches nothing else.
   if(ObjectFind(0, "Label") >= 0)
      ObjectDelete(0, "Label");
   // RESOLVED in v2.32. "Label" survived the delete above because it was never
   // an object *named* "Label": it was this EA's own HUD rows. B100HudLabel()
   // wrote OBJPROP_TEXT = "" for every empty row, and a label with empty text
   // renders the terminal's default caption rather than nothing. B100HudLabel()
   // now hides empty rows outright, so the delete above only ever has to deal
   // with a genuine stray manual insert. The diagnostics stay because they are
   // cheap and they are what finally showed the object list as it really was.
   B100LogObjectDiagnostics();
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
   B100HarvestHumanBoxes();
   EventSetTimer(60);
   B100MaybeStatus();
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   B100CaptureHeartbeat(g_capture);
   B100HarvestHumanBoxes();
   B100MaybeStatus();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_CLOSE)
      B100CancelBoxOco("EA removed");
   if(g_ind_handle != INVALID_HANDLE)
     {
      ChartIndicatorDelete(0, 0, IND_SHORT);
      IndicatorRelease(g_ind_handle);
      g_ind_handle = INVALID_HANDLE;
     }
   ObjectDelete(0, LINE_MID);
   ObjectDelete(0, LINE_UP);
   ObjectDelete(0, LINE_DN);
   ObjectDelete(0, LBL_SIG);
   ObjectDelete(0, LBL_LV);
   ObjectDelete(0, LBL_HUM);
   ObjectDelete(0, LBL_MODE);
   ObjectDelete(0, LBL_BUY1);
   ObjectDelete(0, LBL_BUY2);
   ObjectDelete(0, LBL_SELL1);
   ObjectDelete(0, LBL_SELL2);
   ObjectDelete(0, LBL_BOXINFO);
   ObjectDelete(0, LBL_MODEL);
   ObjectsDeleteAll(0, "B100H_ok_");
   ObjectDelete(0, LV_ENTRY);
   ObjectDelete(0, LV_SL);
   ObjectDelete(0, LV_TP1);
   ObjectDelete(0, LV_TP2);
   ObjectDelete(0, LV_TP3);
   ObjectDelete(0, LV_ENTRY_L);
   ObjectDelete(0, LV_SL_L);
   ObjectDelete(0, LV_TP1_L);
   ObjectDelete(0, LV_TP2_L);
   ObjectDelete(0, LV_TP3_L);
   ObjectDelete(0, LV_FIBO);
   ObjectDelete(0, BOX_RECT);
   ObjectDelete(0, BOX_RES);
   ObjectDelete(0, BOX_SUP);
   ObjectDelete(0, BOX_MID);
   ObjectDelete(0, BOX_BUY);
   ObjectDelete(0, BOX_SELL);
   ObjectDelete(0, BOX_RES_LBL);
   ObjectDelete(0, BOX_SUP_LBL);
   ObjectDelete(0, HUD_BG);
   ObjectDelete(0, BTN_LIVE);
   ObjectDelete(0, BTN_ENTER);
   ObjectsDeleteAll(0, "B100_ev_");
   ObjectsDeleteAll(0, "B100_hx_");
   ObjectsDeleteAll(0, "B100_box");
   B100LearnerSave(g_learner);
   B100CaptureDeinit(g_capture);
   B100RestoreChartSkin();
   Comment("");
  }

void OnTick()
  {
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   B100CaptureOnTick(g_capture);

   if(!g_ready || g_mode.health != B100_HEALTHY)
     {
      g_signal = "STAND_DOWN";
      g_signal_note = (g_mode.block_reason == "" ? "FAULT" : g_mode.block_reason);
      B100PaintPanel();
      return;
     }

   if(bid <= 0.0 || ask <= 0.0 || ask < bid)
     {
      B100FailClosed(g_mode, "TICK_INVALID");
      g_signal = "STAND_DOWN";
      g_signal_note = "TICK_INVALID";
      B100PaintPanel();
      return;
     }

   string labeled = "";
   int decide_up = 0, decide_dn = 0, decide_bounce = 0, decide_cens = 0;
   int learn_side = 0;
   double learn_mfe = 0, learn_mae = 0, learn_hw = 0;
   bool arm_now = false;

   if(InpStrategy == B100_STRAT_BOX_M30)
     {
      labeled = B100BoxOnTick(g_box, InpBoxTF, InpBoxMinBars, InpBoxMaxBars,
                              InpBoxAtrPeriod, InpBoxH4Frac, InpBoxWiden, InpImpulseK, InpBoxTimeout, bid, ask);
      if(g_box.just_armed)
        {
         if(InpUseLearner)
            B100LearnerPolicy(g_learner, 0, g_policy);
         B100BoxApplyDirGate(g_box, (InpUseLearner ? g_policy.dir_gate : "BOTH"));
         B100CaptureSetup(g_capture, g_box, bid, ask);
         if(InpTrainLog)
            B100TrainArm(g_episode, g_box, bid, ask, g_learner.last_arm);
         // Shadow every armed box, unfiltered and in every mode. Arming here —
         // before B100ArmBoxOco, which can decline for any of eight reasons —
         // is what makes the ledger a counterfactual instead of a copy of the
         // trade blotter. The decision string is stamped on afterwards.
         if(InpShadowLedger)
           {
            B100ShadowTag(g_shadow, g_box.armed_bar, g_box.height, ask - bid,
                          g_box.touches_hi, g_box.touches_lo, g_box.close_loc,
                          g_box.compress, g_box.h_vs_h4, g_box.imp_dir, g_box.phase);
            B100ShadowSetDecision(g_shadow, "PENDING");
            B100FillBoxLevels(1, g_box.buy_stop, ask, bid);
            const double s_sl_buy = g_levels.sl, s_tp_buy = g_levels.tp1;
            B100FillBoxLevels(-1, g_box.sell_stop, ask, bid);
            const double s_sl_sell = g_levels.sl, s_tp_sell = g_levels.tp1;
            g_levels.valid = false;
            const double s_lots = B100StopRiskLots(AccountInfoDouble(ACCOUNT_EQUITY),
                                                   InpRiskFraction, g_box.buy_stop, s_sl_buy);
            B100ShadowArmOco(g_shadow, g_box.buy_stop, g_box.sell_stop,
                             s_sl_buy, s_sl_sell, s_tp_buy, s_tp_sell,
                             MathMax(s_lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)));
           }
         arm_now = true;
         Print("BREAK100 OCO both sides  BUY ", DoubleToString(g_box.buy_stop, _Digits),
               "  SELL ", DoubleToString(g_box.sell_stop, _Digits),
               "  (alerting both rails; execution gate=", g_policy.dir_gate, ")");
         g_box.just_armed = false;
        }
      if(labeled != "")
        {
         g_last_event = labeled;
         learn_side = g_box.last_side;
         learn_mfe  = g_box.last_mfe;
         learn_mae  = g_box.last_mae;
         learn_hw   = g_box.last_hw;
         B100LearnerPolicy(g_learner, learn_side, g_policy);
         if(labeled == "CENSORED_OR_AMBIGUOUS")
            B100CancelBoxOco("timeout / both sides hit");
         else if(labeled == "BREAKOUT_UP")
           {
            B100FillBoxLevels(1, g_box.buy_stop, ask, bid);
            B100TelegramFill(1, g_box.buy_stop, true);
           }
         else if(labeled == "BREAKOUT_DOWN")
           {
            B100FillBoxLevels(-1, g_box.sell_stop, ask, bid);
            B100TelegramFill(-1, g_box.sell_stop, true);
           }
        }
      decide_up     = g_box.n_break_up;
      decide_dn     = g_box.n_break_dn;
      decide_bounce = 0;
      decide_cens   = g_box.n_fail;
      B100PaintBox();
     }
   else
     {
      labeled = B100Ingest(g_pipe, bid, ask);
      if(labeled != "")
        {
         g_last_event = labeled;
         learn_side = g_pipe.last_label_side;
         learn_mfe  = g_pipe.last_mfe;
         learn_mae  = g_pipe.last_mae;
         learn_hw   = g_pipe.last_hw;
         B100LearnerPolicy(g_learner, learn_side, g_policy);
        }
      decide_up     = g_pipe.n_break_up;
      decide_dn     = g_pipe.n_break_dn;
      decide_bounce = g_pipe.n_bounce;
      decide_cens   = g_pipe.n_censored;
     }

   B100Costs costs;
   costs.spread     = InpCostSpread;
   costs.commission = InpCostCommission;
   costs.slippage   = InpCostSlippage;

   B100Decide(g_decision,
              decide_up, decide_dn, decide_bounce, decide_cens,
              costs, InpUncertaintyK, InpMinSamples,
              (g_mode.health == B100_HEALTHY),
              B100BrokerOrderIntentPermitted(g_mode));

   B100RiskSnap snap;
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   snap.loss_24h         = 0.0;
   snap.loss_week        = 0.0;
   snap.drawdown         = (balance > 0.0 && equity < balance) ? (balance - equity) / balance : 0.0;
   snap.open_for_symbol  = B100CountMagicPositions();
   if(snap.open_for_symbol == 0 && g_shadow.open)
      snap.open_for_symbol = 1;
   g_risk_code = B100RiskGate(snap);
   if(g_mode.mode == B100_DEMO &&
      g_risk_code != "RISK_GATE_PASSED" &&
      g_risk_code != "MAX_POSITION_REACHED")
      B100Halt(g_mode, g_risk_code);

   // Keep the exec adapter in step with the mode gate. Without this the chart
   // button reads ARMED while every live OrderSend is refused inside DemoExec.
   g_b100_exec_live_ok = B100LiveArmed(g_mode);
   if(arm_now)
      B100ArmBoxOco(bid, ask);

   // Shadow steps in EVERY mode so a continuous benchmark accrues even in
   // OBSERVE (which a real account is forced into). Announcements below stay
   // gated to SHADOW so OBSERVE does not send Telegram alerts for virtual fills.
   const bool shadow_was_open = g_shadow.open;
   if(InpShadowLedger)
      B100ShadowStep(bid, ask, labeled);
   const bool shadow_closed = (shadow_was_open && !g_shadow.open);
   if(g_mode.mode == B100_SHADOW && InpShadowLedger && g_shadow.last_event != "")
     {
      if(g_shadow.last_event == "FILL_BUY")
        {
         g_oco_fill_dir = 1;
         g_oco_fill_px  = g_shadow.entry;
         B100FibLatch(1, g_shadow.entry, g_oco_sl_buy, g_oco_tp_buy,
                      (g_levels.valid ? g_levels.tp2 : 0.0),
                      (g_levels.valid ? g_levels.tp3 : 0.0));
        }
      else if(g_shadow.last_event == "FILL_SELL")
        {
         g_oco_fill_dir = -1;
         g_oco_fill_px  = g_shadow.entry;
         B100FibLatch(-1, g_shadow.entry, g_oco_sl_sell, g_oco_tp_sell,
                      (g_levels.valid ? g_levels.tp2 : 0.0),
                      (g_levels.valid ? g_levels.tp3 : 0.0));
        }
      else if(StringFind(g_shadow.last_event, "CLOSE_") == 0)
         B100TelegramClose(g_shadow.last_event, g_oco_fill_dir, g_oco_fill_px,
                           (g_oco_fill_dir >= 0 ? bid : ask),
                           (g_oco_fill_dir > 0 ? g_oco_sl_buy : g_oco_sl_sell),
                           (g_oco_fill_dir > 0 ? g_oco_tp_buy : g_oco_tp_sell),
                           g_shadow.last_pnl_pts);
     }

   B100ComputeSignal(labeled, shadow_was_open, shadow_closed, bid, ask);
   if(InpStrategy == B100_STRAT_BOX_M30 && labeled == "" &&
      (g_signal == "WAIT" || g_signal == "WATCH"))
     {
      const double mid = 0.5 * (bid + ask);
      g_signal = "WATCH";
      g_signal_note = B100BoxWatchNote(g_box, mid);
      if(!g_box.ready)
        {
         g_signal = "WAIT";
        }
     }
   if(labeled != "")
     {
      const bool fresh = (InpStrategy != B100_STRAT_BOX_M30 || g_box.armed_bar != g_last_learn_bar);
      if(fresh)
        {
         if(InpStrategy == B100_STRAT_BOX_M30)
            B100CaptureOutcome(g_capture, g_box, labeled, bid, ask);
         if(InpStrategy == B100_STRAT_BOX_M30 && labeled == "CENSORED_OR_AMBIGUOUS")
           {
            if(InpTrainLog)
               B100TrainFail(g_episode, labeled);
            // Never filled, so there is no fill-relative path: both extremes sit at bar 0.
            B100LearnerObserve(g_learner, learn_side, labeled, learn_mfe, learn_mae, learn_hw,
                               0, 0, (int)InpStrategy);
            B100LearnerSave(g_learner);
           }
         else if(InpStrategy == B100_STRAT_BOX_M30)
           {
            B100FillBoxLevels(learn_side, (learn_side > 0 ? g_box.buy_stop : g_box.sell_stop), ask, bid);
            if(InpTrainLog && g_levels.valid)
              {
               B100TrainFill(g_episode, learn_side, labeled,
                             g_levels.entry, g_levels.sl, g_levels.tp1, g_levels.tp2, g_levels.tp3);
               B100FibLatch(learn_side, g_levels.entry, g_levels.sl, g_levels.tp1, g_levels.tp2, g_levels.tp3);
              }
           }
         else
           {
            B100LearnerObserve(g_learner, learn_side, labeled, learn_mfe, learn_mae, learn_hw,
                               0, 0, (int)InpStrategy);
            B100LearnerSave(g_learner);
           }
         g_last_learn_bar = g_box.armed_bar;
        }
      if((g_signal == "BUY" || g_signal == "SELL") && g_levels.valid)
        {
         const string sid = "B100-" + IntegerToString((int)g_box.armed_bar);
         const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
         const double lots = B100StopRiskLots(eq, InpRiskFraction, g_levels.entry, g_levels.sl);
         const double risk_amt = eq * B100ClampRiskFraction(InpRiskFraction);
         const double rr = (g_levels.r > 0.0) ? MathAbs(g_levels.tp1 - g_levels.entry) / g_levels.r : 0.0;
         B100WriteSignalJson(g_signal, g_levels.entry, g_levels.sl, g_levels.tp1, g_levels.tp2,
                             lots, risk_amt, rr, g_decision.safe_ev, g_signal_note, sid, "BOX_OCO_UCB_v1");
         // M30 box: pending OCO is the only broker path (armed on WATCH).
         // Channel may still market-send on a demo account.
         if(InpStrategy != B100_STRAT_BOX_M30 &&
            B100BrokerOrderIntentPermitted(g_mode) && g_box.armed_bar != g_last_exec_bar && lots > 0.0)
           {
            string err = "";
            const int dir = (g_signal == "BUY") ? 1 : -1;
            if(B100DemoSend(dir, g_levels.sl, g_levels.tp1, lots, sid, err))
               g_last_exec_bar = g_box.armed_bar;
            else if(err != "MAX_POSITION_REACHED" && err != "EA_TRADE_DISABLED" && err != "TERMINAL_TRADE_DISABLED")
               B100Halt(g_mode, err);
            else
               Print("B100 DemoExec skipped ", err);
           }
        }
     }
   const bool path_live = (InpTrainLog && g_episode.active && g_episode.tracking);
   const bool path_closed = (InpTrainLog && B100TrainStep(g_episode, bid, ask, InpTrainHorizon));
   // Episode tracking (MFE/MAE for the learner) must keep running unconditionally
   // in every mode, real position or not — only the Telegram SEND is gated. With
   // a real two-leg position open, this price-driven progression fires on the
   // same rail crossing that OnTradeTransaction's real DEAL_ENTRY_OUT fires on,
   // producing a second, differently-worded "TP1 HIT" for the identical event.
   // The real-fill message (leg1-vs-runner aware) is authoritative whenever a
   // real position exists; episode-based alerts are the ONLY source when there
   // is none (OBSERVE/SHADOW), so they stay live there.
   const bool have_real_position = (B100CountMagicPositions() > 0);
   if((path_live || path_closed) && !have_real_position)
     {
      const double px_now = (g_episode.side > 0 ? bid : ask);
      int max_hit = 0;
      if(g_episode.hit_tp1 == 1)
         max_hit = 1;
      if(g_episode.hit_tp2 == 1)
         max_hit = 2;
      if(g_episode.hit_tp3 == 1)
         max_hit = 3;
      // Late catch-up (ENTRY after price already ran): one TP message, not TP1+TP2+TP3 spam.
      if(max_hit > g_tg_tp_announced)
        {
         if(g_tg_tp_announced == 0 && max_hit >= 2)
            B100TelegramTp(max_hit, px_now);
         else
           {
            for(int lv = g_tg_tp_announced + 1; lv <= max_hit; lv++)
               B100TelegramTp(lv, px_now);
           }
        }
     }
   if(path_closed)
     {
      const double exit_px = (g_episode.side > 0) ? bid : ask;
      const bool skip_sl = ((g_episode.exit_why == "SL" || g_episode.exit_why == "CLOSE_SL") && g_tg_tp_announced >= 1);
      const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      const double pt = (tick > 0.0 ? tick : _Point);
      double pts = 0.0;
      if(pt > 0.0 && g_episode.entry > 0.0)
         pts = (exit_px - g_episode.entry) / pt * (double)g_episode.side;
      if(!skip_sl && !have_real_position)
         B100TelegramClose(g_episode.exit_why, g_episode.side, g_episode.entry, exit_px,
                           g_episode.sl, g_episode.tp1, pts);
      if(g_episode.quality == 1 && g_episode.hw > 0.0)
        {
         B100LearnerObserve(g_learner, g_episode.side, g_episode.label,
                            g_episode.mfe, g_episode.mae, g_episode.hw,
                            g_episode.bars_to_mfe, g_episode.bars_to_mae, (int)InpStrategy);
         B100LearnerSave(g_learner);
         Print("BREAK100 train closed  exit=", g_episode.exit_why,
               " mfe=", DoubleToString(g_episode.mfe, _Digits),
               " mae=", DoubleToString(g_episode.mae, _Digits),
               " q=", g_episode.quality);
        }
      else
         Print("BREAK100 train discarded  q=", g_episode.quality, " ", g_episode.q_reason);
      B100FibClear();
     }
   B100ManageRunner(bid, ask);
   B100UpdateLines();
   B100PaintLevels();
   B100PaintPanel();
   B100LiveButtonPaint();
   B100EnterButtonPaint();
   B100LogNewBar(labeled);
  }

int B100Pts(const double a, const double b)
  {
   if(a <= 0.0 || b <= 0.0)
      return 0;
   return (int)MathRound(MathAbs(a - b));
  }

string B100Px(const double x)
  {
   if(x <= 0.0)
      return "-";
   return DoubleToString(x, _Digits);
  }

void B100FillSlTpFallback(const int dir, const double px, double &sl, double &tp1, double &tp2, double &tp3)
  {
   sl  = (dir > 0) ? g_oco_sl_buy  : g_oco_sl_sell;
   tp1 = (dir > 0) ? g_oco_tp_buy  : g_oco_tp_sell;
   tp2 = 0.0;
   tp3 = 0.0;
   if(sl <= 0.0 && g_box.height > 0.0)
      sl = (dir > 0) ? g_box.low : g_box.high;
   if(g_levels.valid && g_levels.dir == dir)
     {
      if(sl <= 0.0)
         sl = g_levels.sl;
      if(tp1 <= 0.0)
         tp1 = g_levels.tp1;
      tp2 = g_levels.tp2;
      tp3 = g_levels.tp3;
     }
   if(tp1 <= 0.0 && g_box.height > 0.0 && px > 0.0)
     {
      const double h = g_box.height;
      tp1 = px + dir * h * MathMax(g_policy.tp1_r, InpTp1R);
      tp2 = px + dir * h * MathMax(g_policy.tp2_r, InpTp2R);
      tp3 = px + dir * h * MathMax(g_policy.tp3_r, InpTp3R);
     }
   if(dir > 0)
     {
      if(g_oco_sl_buy <= 0.0)
         g_oco_sl_buy = sl;
      if(g_oco_tp_buy <= 0.0)
         g_oco_tp_buy = tp1;
     }
   else if(dir < 0)
     {
      if(g_oco_sl_sell <= 0.0)
         g_oco_sl_sell = sl;
      if(g_oco_tp_sell <= 0.0)
         g_oco_tp_sell = tp1;
     }
  }

bool B100TgChart(void)
  {
   return (Period() == PERIOD_M30 && InpBoxTF == PERIOD_M30);
  }

void B100Tg(const string text)
  {
   if(!InpTelegram || !B100TgChart())
      return;
   B100TelegramSend(text);
  }

string B100TgKey(const string kind)
  {
   return _Symbol + "|" + kind + "|" + IntegerToString((int)g_box.armed_bar);
  }

void B100OcoClearTickets(void)
  {
   g_oco_buy_tk   = 0;
   g_oco_sell_tk  = 0;
   g_oco_buy_tk2  = 0;
   g_oco_sell_tk2 = 0;
   g_runner_stage = 0;
   g_oco_armed    = false;
  }

// Record a manual (magic 0) deal into the shadow ledger so the operator's own
// discretion becomes labelled training data. Entry deals are remembered; the
// closing deal writes one row using the same 23-column schema as the
// counterfactual rows, so both are directly comparable.
void B100ManualDeal(const ulong deal)
  {
   const long entry_type = HistoryDealGetInteger(deal, DEAL_ENTRY);
   const long deal_type  = HistoryDealGetInteger(deal, DEAL_TYPE);
   const double px       = HistoryDealGetDouble(deal, DEAL_PRICE);
   if(px <= 0.0)
      return;

   if(entry_type == DEAL_ENTRY_IN)
     {
      g_man_dir    = (deal_type == DEAL_TYPE_BUY) ? 1 : -1;
      g_man_entry  = px;
      g_man_sl     = HistoryDealGetDouble(deal, DEAL_SL);
      g_man_lots   = HistoryDealGetDouble(deal, DEAL_VOLUME);
      g_man_opened = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      Print("B100 MANUAL entry ", (g_man_dir > 0 ? "BUY " : "SELL "),
            DoubleToString(px, _Digits), " lots=", DoubleToString(g_man_lots, 2),
            " sl=", DoubleToString(g_man_sl, _Digits), " — tracking for the ledger");
      return;
     }
   if(entry_type != DEAL_ENTRY_OUT || g_man_dir == 0)
      return;

   // Risk basis: the stop the operator actually set. If none, fall back to the
   // current box geometry so the row still carries a comparable R.
   double risk = (g_man_sl > 0.0) ? MathAbs(g_man_entry - g_man_sl) : 0.0;
   if(risk <= 0.0 && g_box.height > 0.0)
      risk = g_box.height * (1.0 + MathMax(InpBoxSlBuf, 0.0));

   B100ShadowBook m;
   B100ShadowInit(m);
   m.lots       = g_man_lots;
   m.height     = g_box.height;
   m.spread_arm = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   m.armed_bar  = g_box.armed_bar;
   m.phase      = g_box.phase;
   m.touches_hi = g_box.touches_hi;
   m.touches_lo = g_box.touches_lo;
   m.close_loc  = g_box.close_loc;
   m.compress   = g_box.compress;
   m.h_vs_h4    = g_box.h_vs_h4;
   m.imp_dir    = g_box.imp_dir;
   m.exec_decision = "MANUAL";
   const double sl_for_r = (risk > 0.0) ? (g_man_entry - g_man_dir * risk) : g_man_sl;
   B100ShadowLedgerRow(m, g_man_dir, g_man_entry, sl_for_r, 0.0, px, "MANUAL_CLOSE");
   Print("B100 MANUAL closed ", DoubleToString(px, _Digits),
         "  R=", (risk > 0.0 ? DoubleToString((px - g_man_entry) * g_man_dir / risk, 3) : "n/a"),
         " — written to shadow ledger");
   g_man_dir = 0;
   g_man_entry = 0;
   g_man_sl = 0;
   g_man_lots = 0;
  }

// Currency risk for a stop distance and volume, so the alert states what a leg
// actually costs instead of leaving the reader to work it out.
double B100MoneyRisk(const double dist, const double lots)
  {
   const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tval = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick <= 0.0 || tval <= 0.0 || dist <= 0.0)
      return 0.0;
   return dist / tick * tval * lots;
  }

// Runner management, ported from the sibling BREAK100_TELEGRAM_OCO_EA.
// TP1 touched  -> runner stop to entry + costs (risk removed)
// TP2 touched  -> runner stop to TP1          (profit locked)
// The runner's own target stays at TP3. Identified by its ":R" comment marker so
// it is still found after a restart, when the ticket is long gone.
void B100ManageRunner(const double bid, const double ask)
  {
   if(!InpTwoLegs || g_oco_fill_dir == 0 || !g_levels.valid)
      return;
   const int dir = g_oco_fill_dir;
   const bool tp1_touched = (dir > 0) ? (bid >= g_levels.tp1) : (ask <= g_levels.tp1);
   if(!tp1_touched)
      return;
   const bool tp2_touched = (dir > 0) ? (bid >= g_levels.tp2) : (ask <= g_levels.tp2);
   const int want_stage = tp2_touched ? 2 : 1;
   if(want_stage <= g_runner_stage)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != B100_MAGIC)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), ":R") < 0)
         continue;

      const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      const double costs = MathMax(ask - bid, _Point) * 2.0;
      const double want  = (want_stage == 2) ? g_levels.tp1 : (entry + dir * costs);
      const double cur   = PositionGetDouble(POSITION_SL);
      // Only ever tighten. A wider stop would silently increase risk.
      if(cur > 0.0 && ((dir > 0 && want <= cur) || (dir < 0 && want >= cur)))
         continue;
      string err = "";
      if(B100ModifyPositionSl(ticket, want, g_levels.tp3, err))
        {
         g_runner_stage = want_stage;
         Print("B100 runner stage ", want_stage,
               (want_stage == 2 ? " — stop to TP1 " : " — stop to breakeven "),
               DoubleToString(want, _Digits));
        }
      else
         Print("B100 runner stop move FAILED ", err);
     }
  }

void B100TgThreadSave(void)
  {
   const int fh = FileOpen("BREAK100_tg_thread.txt", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return;
   FileWriteString(fh, "armed=" + IntegerToString((int)g_tg_thread_bar) + "\n");
   FileWriteString(fh, "watch=" + IntegerToString((int)g_tg_watch_id) + "\n");
   FileWriteString(fh, "entry=" + IntegerToString((int)g_tg_entry_id) + "\n");
   FileWriteString(fh, "tp=" + IntegerToString(g_tg_tp_announced) + "\n");
   FileClose(fh);
  }

void B100TgThreadLoad(void)
  {
   const int fh = FileOpen("BREAK100_tg_thread.txt", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(fh == INVALID_HANDLE)
      return;
   while(!FileIsEnding(fh))
     {
      string line = FileReadString(fh);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringFind(line, "armed=") == 0)
         g_tg_thread_bar = (datetime)StringToInteger(StringSubstr(line, 6));
      else if(StringFind(line, "watch=") == 0)
         g_tg_watch_id = StringToInteger(StringSubstr(line, 6));
      else if(StringFind(line, "entry=") == 0)
         g_tg_entry_id = StringToInteger(StringSubstr(line, 6));
      else if(StringFind(line, "tp=") == 0)
         g_tg_tp_announced = (int)StringToInteger(StringSubstr(line, 3));
     }
   FileClose(fh);
  }

long B100TgParent(void)
  {
   if(g_tg_entry_id > 0)
      return g_tg_entry_id;
   return g_tg_watch_id;
  }

void B100TelegramWatch(void)
  {
   const string key = B100TgKey("WATCH");
   if(B100TgSeen(key))
      return;
   if(g_box.armed_bar != g_tg_thread_bar)
     {
      g_tg_watch_id = 0;
      g_tg_entry_id = 0;
      g_tg_tp_announced = 0;
      g_tg_thread_bar = g_box.armed_bar;
     }
   const double lots_per_leg = MathMax(InpLotsPerLeg, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   const double spread_now   = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                                       SymbolInfoDouble(_Symbol, SYMBOL_BID), _Point);
   const double h_spreads    = (spread_now > 0.0) ? g_box.height / spread_now : 0.0;

   string msg = B100TgSigHead(true);
   msg += "BREAK100  WATCH\n";
   msg += _Symbol + "  M30\n";
   if(g_oco_buy_px > 0.0)
     {
      msg += "BUY STOP  " + B100Px(g_oco_buy_px) + "\n";
      msg += "   SL  " + B100Px(g_oco_sl_buy) + "   risk " +
             DoubleToString(B100MoneyRisk(MathAbs(g_oco_buy_px - g_oco_sl_buy), lots_per_leg), 2) +
             "/leg\n";
      msg += "   TP1 " + B100Px(g_oco_tp_buy);
      if(g_oco_tp3_buy > 0.0 && g_oco_tp3_buy != g_oco_tp_buy)
         msg += "   TP3 " + B100Px(g_oco_tp3_buy) + " (runner)";
      msg += "\n";
     }
   if(g_oco_sell_px > 0.0)
     {
      msg += "SELL STOP  " + B100Px(g_oco_sell_px) + "\n";
      msg += "   SL  " + B100Px(g_oco_sl_sell) + "   risk " +
             DoubleToString(B100MoneyRisk(MathAbs(g_oco_sell_px - g_oco_sl_sell), lots_per_leg), 2) +
             "/leg\n";
      msg += "   TP1 " + B100Px(g_oco_tp_sell);
      if(g_oco_tp3_sell > 0.0 && g_oco_tp3_sell != g_oco_tp_sell)
         msg += "   TP3 " + B100Px(g_oco_tp3_sell) + " (runner)";
      msg += "\n";
     }
   msg += "\nbox " + DoubleToString(g_box.height, _Digits) +
          " = " + DoubleToString(h_spreads, 1) + "x spread";
   if(InpMinBoxSpreads > 0.0)
      msg += (h_spreads >= InpMinBoxSpreads ? "  [above trade floor]" : "  [BELOW trade floor]");
   msg += "\n";
   // Sample size travels with the estimate on purpose: a probability from 14
   // closed trades and one from 400 must not read the same.
   msg += "model n=" + IntegerToString(g_policy.n) + " (" + g_policy.source + ")";
   if(g_policy.mean_r != 0.0)
      msg += "  measured " + DoubleToString(g_policy.mean_r, 3) + "R/trade";
   msg += "\n";
   msg += (B100BrokerOrderIntentPermitted(g_mode)
           ? "auto-trade ON (" + B100ModeName(g_mode.mode) + ")"
           : "auto-trade OFF (" + B100ModeName(g_mode.mode) + ") - manual only");
   msg += "\n";
   if(g_oco_buy_px > 0.0 && g_oco_sell_px > 0.0)
      msg += "OCO: first fill cancels the other.";
   else
      msg += "One-side stop.";
   if(!InpTelegram || !B100TgChart())
      return;
   const long id = B100TelegramOnceReply(key, msg, 0);
   if(id > 0)
     {
      g_tg_watch_id = id;
      g_tg_thread_bar = g_box.armed_bar;
      B100TgThreadSave();
     }
  }

void B100TelegramFill(const int dir, const double px, const bool sibling_deleted)
  {
   const string key = B100TgKey(dir > 0 ? "ENTRY_BUY" : "ENTRY_SELL");
   if(B100TgSeen(key))
      return;
   g_oco_fill_dir = dir;
   g_oco_fill_px  = px;
   string err = "";
   if(sibling_deleted && B100BrokerOrderIntentPermitted(g_mode))
     {
      if(dir > 0 && g_oco_sell_tk != 0)
        {
         B100DemoCancelTicket(g_oco_sell_tk, err);
         g_oco_sell_tk = 0;
        }
      else if(dir < 0 && g_oco_buy_tk != 0)
        {
         B100DemoCancelTicket(g_oco_buy_tk, err);
         g_oco_buy_tk = 0;
        }
     }
   // This tick-based path typically reacts to a crossed rail before the
   // broker's async DEAL_ENTRY_IN confirmation reaches OnTradeTransaction, so
   // it must retire the runner leg too, not just leg 1 — otherwise the losing
   // side's runner pending is left resting until OnTradeTransaction catches up.
   if(sibling_deleted && B100BrokerOrderIntentPermitted(g_mode))
     {
      if(dir > 0 && g_oco_sell_tk2 != 0)
        {
         B100DemoCancelTicket(g_oco_sell_tk2, err);
         g_oco_sell_tk2 = 0;
        }
      else if(dir < 0 && g_oco_buy_tk2 != 0)
        {
         B100DemoCancelTicket(g_oco_buy_tk2, err);
         g_oco_buy_tk2 = 0;
        }
     }
   double sl = 0, tp1 = 0, tp2 = 0, tp3 = 0;
   if(g_levels.valid && g_levels.dir == dir)
     {
      sl  = g_levels.sl;
      tp1 = g_levels.tp1;
      tp2 = g_levels.tp2;
      tp3 = g_levels.tp3;
     }
   else
      B100FillSlTpFallback(dir, px, sl, tp1, tp2, tp3);
   B100FibLatch(dir, px, sl, tp1, tp2, tp3);
   const string side = (dir > 0) ? "BUY" : "SELL";
   const string face = (dir > 0) ? "🟢" : "🔴";
   string msg = B100TgSigHead(false);
   msg += face + " BREAK100  ENTRY " + side + "\n";
   msg += _Symbol + "  @ " + B100Px(px) + "\n";
   msg += "🛑 SL   " + B100Px(sl);
   const int slp = B100Pts(px, sl);
   if(slp > 0)
      msg += "  (" + IntegerToString(slp) + " pts)";
   msg += "\n🎯 TP1  " + B100Px(tp1);
   if(tp2 > 0.0)
      msg += "\n🎯 TP2  " + B100Px(tp2);
   if(tp3 > 0.0)
      msg += "\n🎯 TP3  " + B100Px(tp3);
   if(sibling_deleted)
      msg += (dir > 0 ? "\nSELL STOP cancelled" : "\nBUY STOP cancelled");
   g_tg_tp_announced = 0;
   if(!InpTelegram || !B100TgChart())
      return;
   const long id = B100TelegramOnceReply(key, msg, g_tg_watch_id);
   if(id > 0)
     {
      g_tg_entry_id = id;
      g_tg_thread_bar = g_box.armed_bar;
      B100TgThreadSave();
     }
  }

void B100TelegramCancel(const string reason)
  {
   const string key = B100TgKey("CANCEL");
   string msg = B100TgSigHead(false);
   msg += "⚪ BREAK100  CANCEL\n";
   msg += _Symbol + "  M30\n";
   msg += reason;
   if(!InpTelegram || !B100TgChart())
      return;
   B100TelegramOnceReply(key, msg, (g_tg_watch_id > 0 ? g_tg_watch_id : 0));
  }

void B100TelegramTp(const int level, const double px)
  {
   if(level < 1 || level > 3)
      return;
   if(g_tg_tp_announced >= level)
      return;
   const string key = B100TgKey("TP" + IntegerToString(level));
   string msg = B100TgSigHead(false);
   msg += "✅ BREAK100  TP" + IntegerToString(level) + " HIT\n";
   msg += _Symbol + "  @ " + B100Px(px);
   if(g_episode.entry > 0.0)
      msg += "\nfrom ENTRY " + B100Px(g_episode.entry);
   if(g_tg_tp_announced == 0 && level >= 2)
      msg += "\n(price already through TP1" + (level >= 3 ? "/TP2" : "") + ")";
   if(!InpTelegram || !B100TgChart())
      return;
   if(B100TelegramOnceReply(key, msg, B100TgParent()) > 0 || B100TgSeen(key))
     {
      g_tg_tp_announced = level;
      B100TgThreadSave();
     }
  }

void B100TelegramClose(const string why, const int dir, const double entry, const double exit_px, const double sl, const double tp, const double pts, const bool is_runner)
  {
   // With two legs, "CLOSE" now fires twice per trade — once when leg 1 hits
   // TP1 (the runner is still open at that point) and again whenever the
   // runner itself closes. Without is_runner, leg 1's own TP1 read as generic
   // "TP HIT" (ambiguous with a full close) and a runner closing via its
   // trailed stop — which by then may sit at breakeven or TP1, i.e. flat or
   // profitable — read as "SL HIT", which looks like a loss even when the pts
   // result printed below it is positive.
   B100FibClear();
   string tag = why;
   string face = "⚪";
   if(why == "CLOSE_SL" || why == "SL")
     {
      tag = is_runner ? "RUNNER STOP" : "SL HIT";
      face = is_runner ? "🏁" : "❌";
     }
   else if(why == "CLOSE_TP" || why == "TP" || why == "TP1" || why == "TP2" || why == "TP3" ||
           why == "TP3" || why == "TP2_H" || why == "TP1_H")
     {
      tag = is_runner ? "RUNNER TP" : "TP1 HIT — runner continues";
      face = "✅";
      if(why == "TP2_H")
         tag = "TP2 HIT";
      if(why == "TP1_H")
         tag = "TP1 HIT";
      if(why == "TP3")
         tag = "TP3 HIT";
     }
   else if(why == "HORIZON")
     {
      tag = "TIME EXIT";
      face = "⏰";
     }
   else if(StringFind(why, "CLOSE_") == 0)
      tag = StringSubstr(why, 6);
   const string side = (dir > 0) ? "BUY" : ((dir < 0) ? "SELL" : "?");
   const string key = B100TgKey("CLOSE_" + tag + (is_runner ? "_R" : ""));
   string msg = B100TgSigHead(false);
   msg += face + " BREAK100  " + tag + "  " + side + "\n";
   msg += _Symbol + "\n";
   msg += "Entry " + B100Px(entry) + "  →  Exit " + B100Px(exit_px) + "\n";
   if(sl > 0.0)
      msg += "SL " + B100Px(sl) + "   ";
   if(tp > 0.0)
      msg += "TP " + B100Px(tp);
   msg += "\n";
   const int ip = (int)MathRound(pts);
   if(ip > 0)
      msg += "Result  +" + IntegerToString(ip) + " pts";
   else if(ip < 0)
      msg += "Result  " + IntegerToString(ip) + " pts";
   else
      msg += "Result  flat";
   if(!InpTelegram || !B100TgChart())
      return;
   if(!is_runner && (tag == "TP1 HIT" || tag == "TP2 HIT" || tag == "TP3 HIT" ||
                     tag == "TP1 HIT — runner continues") && g_tg_tp_announced >= 1)
      return;
   B100TelegramOnceReply(key, msg, B100TgParent());
  }

datetime B100StatusReadGmt(void)
  {
   const int fh = FileOpen("BREAK100_tg_status.txt", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(fh == INVALID_HANDLE)
      return 0;
   string s = FileReadString(fh);
   FileClose(fh);
   StringTrimLeft(s);
   StringTrimRight(s);
   return (datetime)StringToInteger(s);
  }

void B100StatusWriteGmt(const datetime t)
  {
   const int fh = FileOpen("BREAK100_tg_status.txt", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return;
   FileWriteString(fh, IntegerToString((int)t));
   FileClose(fh);
  }

void B100TelegramStatus(void)
  {
   string msg = "📊 " + TimeToString(TimeGMT(), TIME_MINUTES) + " GMT\n";
   if(g_mode.health != B100_HEALTHY)
      msg += "⚠️ " + B100ModeName(g_mode.mode) + "  " + g_mode.block_reason + "\n";
   else if(g_mode.mode == B100_SHADOW)
      msg += "👻 SHADOW\n";
   else if(g_mode.mode == B100_DEMO)
      msg += "🧪 DEMO\n";
   else
      msg += "👁 " + B100ModeName(g_mode.mode) + "\n";

   if(g_capture.last_bar_time[3] > 0)
      msg += "✅ M30 " + TimeToString(g_capture.last_bar_time[3], TIME_MINUTES) + "\n";
   else
      msg += "⚠️ no M30\n";

   if(g_episode.tracking)
      msg += "📍 PATH\n";
   else if(g_episode.active)
      msg += "📍 ARMED\n";

   int n_u = 0, n_sl = 0, n_tp3 = 0;
   B100TrainBlotterStats(n_u, n_sl, n_tp3);
   msg += "📒 unique " + IntegerToString(n_u);
   msg += "  ❌" + IntegerToString(n_sl);
   msg += "  ✅TP3 " + IntegerToString(n_tp3) + "\n";
   msg += "🧠 policy n=" + IntegerToString(g_policy.n) + "  gate=" +
          (g_box.ready ? g_box.dir_gate : "n/a") + "\n";
   if(g_human_n > 0)
      msg += "📐 human boxes " + IntegerToString(g_human_n) + "\n";

   if(g_policy.sl_r > 0.0)
      msg += "🎯 " + DoubleToString(g_policy.sl_r, 1) + "R → " +
             DoubleToString(g_policy.tp1_r, 1) + "  " +
             DoubleToString(g_policy.tp2_r, 1) + "  " +
             DoubleToString(g_policy.tp3_r, 1) + "\n";

   if(g_box.ready && g_box.state == B100_BOX_ARMED)
     {
      msg += "👀 ";
      if(g_box.allow_buy && g_box.buy_stop > 0.0)
         msg += "🟢 " + DoubleToString(g_box.buy_stop, _Digits) + "  ";
      if(g_box.allow_sell && g_box.sell_stop > 0.0)
         msg += "🔴 " + DoubleToString(g_box.sell_stop, _Digits);
      msg += "\n";
     }
   else
     {
      if(g_box.n_break_up + g_box.n_break_dn + g_box.n_fail > 0)
         msg += "📦 " + IntegerToString(g_box.n_break_up) + "↑  " +
                IntegerToString(g_box.n_break_dn) + "↓  " +
                IntegerToString(g_box.n_fail) + "✗\n";
      if(g_signal == "BUY")
         msg += "🟢 BUY\n";
      else if(g_signal == "SELL")
         msg += "🔴 SELL\n";
      else if(g_signal == "HOLD")
         msg += "📌 HOLD\n";
      else if(g_signal != "")
         msg += "⏳ " + g_signal + "\n";
     }
   B100Tg(msg);
   Print("B100 ML/RL status sent");
  }

void B100TelegramSelfTest(void)
  {
   if(!InpTelegram || !B100TgChart())
      return;
   if(!g_tg_ok)
     {
      Print("B100 Telegram TEST FAIL — missing Common\\Files\\BREAK100_telegram.txt (token= and chat=)");
      return;
     }
   // B100_VERSION so this self-test can never go stale the way the previous
   // hardcoded "v2.19" did — it survived ten releases without being touched.
   string msg = "🧪 BREAK100  v" + B100_VERSION + "  Telegram OK  M30 only\n";
   msg += _Symbol + "  " + B100ModeName(g_mode.mode) + "\n";
   msg += "\nYou will get these alerts:\n";
   msg += "👀 WATCH        both stops, SL, TP1, TP3 (runner)\n";
   msg += "🟢 ENTRY BUY    🔴 ENTRY SELL\n";
   msg += "✅ TP1 HIT — runner continues\n";
   msg += "🏁 RUNNER STOP    ✅ RUNNER TP\n";
   msg += "❌ SL HIT (no runner reached)\n";
   msg += "⏰ TIME EXIT    ⚪ CANCEL\n";
   msg += "\nThis is a one-time test. No live orders.";
   if(B100TelegramOnce("BOOT|1.85|" + _Symbol, msg))
      Print("B100 Telegram TEST sent");
   else
      Print("B100 Telegram TEST skipped (already sent) or HTTP fail — check Experts log and WebRequest https://api.telegram.org");
  }

void B100MaybeStatus(void)
  {
   if(!InpTelegram || !B100TgChart() || InpStatusHours <= 0 || !g_tg_ok)
      return;
   const datetime now = TimeGMT();
   const datetime last = B100StatusReadGmt();
   const int gap = InpStatusHours * 3600;
   if(last != 0 && (now - last) < gap)
      return;
   B100StatusWriteGmt(now);
   B100TelegramStatus();
  }

void B100CancelBoxOco(const string reason)
  {
   if(!g_oco_armed && g_oco_buy_tk == 0 && g_oco_sell_tk == 0 &&
      g_oco_buy_tk2 == 0 && g_oco_sell_tk2 == 0 &&
      !g_shadow.pend_buy && !g_shadow.pend_sell)
      return;
   string err = "";
   if(B100BrokerOrderIntentPermitted(g_mode))
     {
      if(g_oco_buy_tk != 0)
         B100DemoCancelTicket(g_oco_buy_tk, err);
      if(g_oco_sell_tk != 0)
         B100DemoCancelTicket(g_oco_sell_tk, err);
      if(g_oco_buy_tk2 != 0)
         B100DemoCancelTicket(g_oco_buy_tk2, err);
      if(g_oco_sell_tk2 != 0)
         B100DemoCancelTicket(g_oco_sell_tk2, err);
      B100DemoCancelAllPendings();
     }
   B100ShadowCancelOco(g_shadow);
   B100OcoClearTickets();
   B100TelegramCancel(reason);
  }

void B100ArmBoxOco(const double bid, const double ask)
  {
   if(InpStrategy != B100_STRAT_BOX_M30)
      return;
   if(!g_box.ready || g_box.state != B100_BOX_ARMED)
      return;
   if(g_risk_code != "RISK_GATE_PASSED" && g_risk_code != "")
     {
      if(g_risk_code != "MAX_POSITION_REACHED")
         B100ShadowSetDecision(g_shadow, "SKIP_RISK");
      return;
     }
   if(B100CountMagicPositions() > 0)
     {
      B100ShadowSetDecision(g_shadow, "SKIP_OPEN");
      return;
     }

   // Box-size gate. Gap overshoot measured in R scales inversely with box size:
   // a 100-point gap is 2.2R against a 46-point stop but 0.87R against a 115-point
   // one. Backtest over 42 days of ticks: trading only boxes >= 60 moved M30
   // expectancy from -0.164R to -0.040R and halved drawdown. Alerts are NOT gated.
   const double spread_now = MathMax(ask - bid, _Point);
   if(!g_manual_entry_override && InpMinBoxSpreads > 0.0 &&
      g_box.height < InpMinBoxSpreads * spread_now)
     {
      Print("B100 OCO skip — box ", DoubleToString(g_box.height, _Digits),
            " below trade floor ", DoubleToString(InpMinBoxSpreads * spread_now, _Digits),
            " (", DoubleToString(InpMinBoxSpreads, 1), " spreads). Alert still sent.");
      B100ShadowSetDecision(g_shadow, "SKIP_SIZE");
      return;
     }

   // Execution side is gated by the learned policy; detection/alerting is not.
   const bool want_buy  = (g_box.buy_stop > 0.0) && g_box.exec_buy;
   const bool want_sell = (g_box.sell_stop > 0.0) && g_box.exec_sell;
   if(!want_buy && !want_sell)
     {
      Print("B100 OCO skip — no side permitted  gate=", g_box.dir_gate);
      B100ShadowSetDecision(g_shadow, "SKIP_GATE");
      return;
     }

   double buy_px = 0, sl_buy = 0, tp_buy = 0, sell_px = 0, sl_sell = 0, tp_sell = 0;
   if(want_buy)
     {
      B100FillBoxLevels(1, g_box.buy_stop, ask, bid);
      buy_px = g_box.buy_stop;
      sl_buy = g_levels.sl;
      tp_buy = g_levels.tp1;
     }
   if(want_sell)
     {
      B100FillBoxLevels(-1, g_box.sell_stop, ask, bid);
      sell_px = g_box.sell_stop;
      sl_sell = g_levels.sl;
      tp_sell = g_levels.tp1;
     }
   g_levels.valid = false;

   if(want_buy && sl_buy <= 0.0)
     {
      B100ShadowSetDecision(g_shadow, "SKIP_SL_INVALID");
      return;
     }
   if(want_sell && sl_sell <= 0.0)
     {
      B100ShadowSetDecision(g_shadow, "SKIP_SL_INVALID");
      return;
     }
   if(want_buy && want_sell && buy_px <= sell_px)
     {
      B100ShadowSetDecision(g_shadow, "SKIP_RAILS_CROSSED");
      return;
     }
   if(want_buy && !(ask < buy_px))
     {
      Print("B100 skip — ask already through BUY STOP");
      B100ShadowSetDecision(g_shadow, "SKIP_LATE");
      return;
     }
   if(want_sell && !(bid > sell_px))
     {
      Print("B100 skip — bid already through SELL STOP");
      B100ShadowSetDecision(g_shadow, "SKIP_LATE");
      return;
     }

   // Broker minimum distance. BREAK100 reports SYMBOL_TRADE_STOPS_LEVEL = 1000
   // points = 10.00 price units; nothing in this EA honoured it before, so a
   // tight box produced pendings the server rejects outright.
   const double need = B100StopsLevel();
   if(need > 0.0)
     {
      if(want_buy && (!B100FarEnough(buy_px, ask) || !B100FarEnough(buy_px, sl_buy) ||
                      (tp_buy > 0.0 && !B100FarEnough(buy_px, tp_buy))))
        {
         Print("B100 OCO skip — BUY leg inside broker stops level ",
               DoubleToString(need, _Digits));
         B100ShadowSetDecision(g_shadow, "SKIP_STOPS_LEVEL");
         return;
        }
      if(want_sell && (!B100FarEnough(sell_px, bid) || !B100FarEnough(sell_px, sl_sell) ||
                       (tp_sell > 0.0 && !B100FarEnough(sell_px, tp_sell))))
        {
         Print("B100 OCO skip — SELL leg inside broker stops level ",
               DoubleToString(need, _Digits));
         B100ShadowSetDecision(g_shadow, "SKIP_STOPS_LEVEL");
         return;
        }
     }

   // Fixed volume per leg. This deliberately sidesteps per-leg risk splitting:
   // with 0.01 on each leg the combined exposure is known and tiny, and the
   // 0.25% clamp in Risk.mqh is never the binding constraint. Risk-derived
   // sizing is still computed for the alert, just not used for the order.
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double lots = MathMax(InpLotsPerLeg, vmin);
   if(lots <= 0.0)
     {
      Print("B100 OCO skip — lots=0");
      B100ShadowSetDecision(g_shadow, "SKIP_LOTS");
      return;
     }

   g_oco_sid     = "B100-" + IntegerToString((int)g_box.armed_bar);
   g_oco_buy_px  = buy_px;
   g_oco_sell_px = sell_px;
   g_oco_sl_buy  = sl_buy;
   g_oco_sl_sell = sl_sell;
   g_oco_tp_buy  = tp_buy;
   g_oco_tp_sell = tp_sell;
   g_oco_lots    = lots;
   g_oco_fill_dir = 0;
   g_oco_fill_px  = 0;
   g_oco_armed    = true;

   // Shadow is armed in OnTick for every box, filtered or not. Arming it here
   // as well would only ever record boxes that survived all eight gates above.

   if(B100BrokerOrderIntentPermitted(g_mode))
     {
      B100DemoCancelAllPendings();
      string err = "";
      ulong tb = 0, ts = 0, tb2 = 0, ts2 = 0;
      // Runner target: TP3 when we have levels, else fall back to the leg-1 TP
      // so a runner is never sent without a target.
      const double run_tp_buy  = (g_levels.valid && g_levels.tp3 > 0.0) ? g_levels.tp3 : tp_buy;
      const double run_tp_sell = (g_levels.valid && g_levels.tp3 > 0.0) ? g_levels.tp3 : tp_sell;
      // Only advertise a runner target when a runner leg will actually be
      // placed below. Setting these unconditionally meant the WATCH alert and
      // the dashboard both claimed a "TP3 (runner)" leg with InpTwoLegs=false,
      // describing an order that was never sent.
      g_oco_tp3_buy  = InpTwoLegs ? run_tp_buy : 0.0;
      g_oco_tp3_sell = InpTwoLegs ? run_tp_sell : 0.0;
      if(want_buy)
        {
         if(!B100DemoPlacePending(ORDER_TYPE_BUY_STOP, buy_px, sl_buy, tp_buy, lots, g_oco_sid + ":B1", tb, err))
           {
            Print("B100 OCO BUY_STOP failed ", err);
            B100OcoClearTickets();
            B100TelegramWatch();
            return;
           }
         if(InpTwoLegs)
           {
            string err_r = "";
            if(!B100DemoPlacePending(ORDER_TYPE_BUY_STOP, buy_px, sl_buy, run_tp_buy, lots,
                                     g_oco_sid + ":R:B2", tb2, err_r))
               Print("B100 runner BUY leg failed ", err_r, " — leg 1 continues alone");
           }
        }
      if(want_sell)
        {
         string err_s = "";
         if(!B100DemoPlacePending(ORDER_TYPE_SELL_STOP, sell_px, sl_sell, tp_sell, lots, g_oco_sid + ":S1", ts, err_s))
           {
            Print("B100 OCO SELL_STOP failed ", err_s);
            string cerr = "";
            if(tb != 0)
               B100DemoCancelTicket(tb, cerr);
            // tb2 (the BUY runner) can already be live at this point — it is
            // placed right after BUY leg 1, before SELL is ever attempted. This
            // was previously left uncancelled: an orphaned, untracked pending
            // that no EA state pointed to, resting on the broker until the next
            // box's B100DemoCancelAllPendings happened to sweep it up.
            if(tb2 != 0)
               B100DemoCancelTicket(tb2, cerr);
            B100OcoClearTickets();
            B100TelegramWatch();
            return;
           }
        }
      if(want_sell && InpTwoLegs)
        {
         string err_r2 = "";
         if(!B100DemoPlacePending(ORDER_TYPE_SELL_STOP, sell_px, sl_sell, run_tp_sell, lots,
                                  g_oco_sid + ":R:S2", ts2, err_r2))
            Print("B100 runner SELL leg failed ", err_r2, " — leg 1 continues alone");
        }
      g_oco_buy_tk   = tb;
      g_oco_sell_tk  = ts;
      g_oco_buy_tk2  = tb2;
      g_oco_sell_tk2 = ts2;
      g_runner_stage = 0;
      g_last_exec_bar = g_box.armed_bar;
     }

   B100ShadowSetDecision(g_shadow,
                         B100BrokerOrderIntentPermitted(g_mode) ? "TRADED" : "SKIP_MODE");
   B100FibClear();
   B100TelegramWatch();
   Print("B100 OCO armed ", (want_buy && want_sell ? "BOTH" : (want_buy ? "BUY only" : "SELL only")),
         "  first fill cancels the other  gate=", g_box.dir_gate,
         " BUY ", DoubleToString(buy_px, _Digits),
         "  SELL ", DoubleToString(sell_px, _Digits),
         "  lots=", DoubleToString(lots, 2),
         "  mode=", B100ModeName(g_mode.mode));
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(InpStrategy != B100_STRAT_BOX_M30)
      return;
   if(trans.symbol != _Symbol && trans.symbol != "")
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0)
     {
      const ulong deal = trans.deal;
      if(!HistoryDealSelect(deal))
         return;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         return;
      const long deal_magic = (long)HistoryDealGetInteger(deal, DEAL_MAGIC);
      if(deal_magic != B100_MAGIC)
        {
         // Manual trades (magic 0) were previously dropped here, so the
         // operator's own discretion never became training data. Record them
         // into the same shadow ledger, tagged MANUAL, alongside the
         // counterfactual rows.
         if(deal_magic == 0 && InpShadowLedger)
            B100ManualDeal(deal);
         return;
        }
      const long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      const long dtype = HistoryDealGetInteger(deal, DEAL_TYPE);
      const double px  = HistoryDealGetDouble(deal, DEAL_PRICE);
      if(entry == DEAL_ENTRY_IN)
        {
         const int dir = (dtype == DEAL_TYPE_BUY) ? 1 : -1;
         string err = "";
         // Both same-side legs sit at one price and fill on the same tick, so
         // the first fill must retire BOTH opposite legs, not just one.
         if(dir > 0)
           {
            if(g_oco_sell_tk != 0)
              {
               B100DemoCancelTicket(g_oco_sell_tk, err);
               g_oco_sell_tk = 0;
              }
            if(g_oco_sell_tk2 != 0)
              {
               B100DemoCancelTicket(g_oco_sell_tk2, err);
               g_oco_sell_tk2 = 0;
              }
           }
         else
           {
            if(g_oco_buy_tk != 0)
              {
               B100DemoCancelTicket(g_oco_buy_tk, err);
               g_oco_buy_tk = 0;
              }
            if(g_oco_buy_tk2 != 0)
              {
               B100DemoCancelTicket(g_oco_buy_tk2, err);
               g_oco_buy_tk2 = 0;
              }
           }
         g_oco_fill_dir = dir;
         g_oco_fill_px  = px;

         // Gapped fills silently break the risk cap. The stop was anchored to the
         // box, but a spike can fill us far past it — real fills on this account
         // have gapped 60-123 points against a 5.00 spread. Left alone, the
         // distance from actual entry to stop exceeds the distance the position
         // was sized for, so the trade risks more than the configured fraction.
         // Re-anchor the stop to the same distance from where we actually filled.
         const double want_px = (dir > 0) ? g_oco_buy_px : g_oco_sell_px;
         const double want_sl = (dir > 0) ? g_oco_sl_buy : g_oco_sl_sell;
         const double want_tp = (dir > 0) ? g_oco_tp_buy : g_oco_tp_sell;
         if(want_px > 0.0 && want_sl > 0.0)
          {
           const double gap     = (px - want_px) * dir;      // >0 = filled worse
           const double sl_dist = MathAbs(want_px - want_sl);
           if(gap > 0.0 && sl_dist > 0.0 && gap > 0.10 * sl_dist)
            {
             const double new_sl = px - dir * sl_dist;
             const double new_tp = (want_tp > 0.0) ? px + dir * MathAbs(want_tp - want_px) : 0.0;
             string merr = "";
             if(B100ModifyPositionSl(trans.position, new_sl, new_tp, merr))
                Print("B100 re-anchored stop after ", DoubleToString(gap, _Digits),
                      " gap: SL ", DoubleToString(want_sl, _Digits), " -> ",
                      DoubleToString(new_sl, _Digits), " (risk held at ",
                      DoubleToString(sl_dist, _Digits), ")");
             else
                Print("B100 re-anchor FAILED ", merr, " — risk now ",
                      DoubleToString(MathAbs(px - want_sl), _Digits),
                      " vs intended ", DoubleToString(sl_dist, _Digits));
             if(dir > 0)
                g_oco_sl_buy = new_sl;
             else
                g_oco_sl_sell = new_sl;
            }
          }
         // ENTRY Telegram only from tick/close box fill — not from the deal callback.
        }
      else if(entry == DEAL_ENTRY_OUT)
        {
         const int dir = (dtype == DEAL_TYPE_SELL) ? 1 : -1;
         const long reason = HistoryDealGetInteger(deal, DEAL_REASON);
         // Deals inherit their originating order/position's comment, the same
         // ":R" marker B100ManageRunner already uses to find the runner
         // position by POSITION_COMMENT — so this is the one place a closing
         // deal can be told apart from leg 1's closing deal.
         const bool is_runner = (StringFind(HistoryDealGetString(deal, DEAL_COMMENT), ":R") >= 0);
         string why = "CLOSE";
         if(reason == DEAL_REASON_SL)
            why = "CLOSE_SL";
         else if(reason == DEAL_REASON_TP)
            why = "CLOSE_TP";
         const double pts = (g_oco_fill_px > 0.0 && SymbolInfoDouble(_Symbol, SYMBOL_POINT) > 0.0)
                            ? ((px - g_oco_fill_px) / SymbolInfoDouble(_Symbol, SYMBOL_POINT) * (double)dir)
                            : 0.0;
         B100TelegramClose(why, dir, g_oco_fill_px, px,
                           (dir > 0 ? g_oco_sl_buy : g_oco_sl_sell),
                           (dir > 0 ? g_oco_tp_buy : g_oco_tp_sell),
                           pts, is_runner);
         // Leg 1 closing (TP1) does not end the trade while the runner is
         // still open — clearing tickets here would spuriously reset
         // g_runner_stage mid-flight (B100ManageRunner self-heals it next
         // tick, but it's needless churn and was flatly wrong once real state
         // depended on it). Only retire tracking once BOTH legs are closed.
         if(B100CountMagicPositions() == 0)
            B100OcoClearTickets();
        }
      return;
     }
  }

void B100FillLevels(const int dir, const double entry, const double ask, const double bid)
  {
   const double spread = MathMax(ask - bid, _Point);
   double sl_hw = InpStopAtrMult;
   double tp2_hw = InpTp2R * sl_hw;
   double tp3_hw = InpTp3R * sl_hw;
   if(InpUseLearner)
     {
      sl_hw  = g_policy.sl_r;
      tp2_hw = g_policy.tp2_r;
      tp3_hw = g_policy.tp3_r;
     }
   double stop_dist = MathMax(sl_hw * g_pipe.half_width, 2.0 * spread);
   if(stop_dist <= 0.0 || dir == 0)
     {
      g_levels.valid = false;
      return;
     }
   g_levels.valid = true;
   g_levels.dir   = dir;
   g_levels.entry = entry;
   g_levels.r     = stop_dist;
   g_levels.sl    = entry - dir * stop_dist;
   const double R = g_levels.r;
   double d2 = MathMax(2.0 * R, tp2_hw * g_pipe.half_width);
   double d3 = MathMax(d2 + 0.2 * R, tp3_hw * g_pipe.half_width);
   g_levels.tp1   = entry + dir * R;
   g_levels.tp2   = entry + dir * d2;
   g_levels.tp3   = entry + dir * d3;
   g_levels.tp_hit= 0;
  }

void B100FillBoxLevels(const int dir, const double entry, const double ask, const double bid)
  {
   const double spread = MathMax(ask - bid, _Point);
   if(!g_box.ready || dir == 0)
     {
      B100FillLevels(dir, entry, ask, bid);
      return;
     }
   double H = g_box.height;
   if(H <= 0.0)
     {
      g_levels.valid = false;
      return;
     }
   double tp1m = InpTp1R, tp2m = InpTp2R, tp3m = InpTp3R;
   if(InpUseLearner)
     {
      tp1m = g_policy.tp1_r;
      tp2m = g_policy.tp2_r;
      tp3m = g_policy.tp3_r;
     }
   const double stop_px = (dir > 0) ? g_box.buy_stop : g_box.sell_stop;
   const double other   = (dir > 0) ? g_box.low : g_box.high;
   double sl_r = 1.0 + MathMax(0.0, InpBoxSlBuf);
   if(InpUseLearner && g_policy.sl_r > 0.0)
      sl_r = MathMax(g_policy.sl_r, 1.0 + InpBoxSlBuf);
   g_levels.valid = true;
   g_levels.dir   = dir;
   g_levels.entry = stop_px;
   g_levels.sl    = stop_px - dir * H * sl_r;
   const double rail = other - dir * MathMax(InpBoxSlBuf, 0.0) * H;
   if(dir > 0)
      g_levels.sl = MathMin(g_levels.sl, rail);
   else
      g_levels.sl = MathMax(g_levels.sl, rail);
   if((dir > 0 && g_levels.sl >= g_levels.entry) || (dir < 0 && g_levels.sl <= g_levels.entry))
      g_levels.sl = g_levels.entry - dir * MathMax(4.0 * spread, 0.5 * H);
   g_levels.r = MathAbs(g_levels.entry - g_levels.sl);
   const double R = g_levels.r;
   g_levels.tp1 = g_levels.entry + dir * R;
   double d2 = 2.0 * R;
   double d3 = 3.0 * R;
   if(InpUseLearner)
     {
      if(tp2m > 0.0)
         d2 = MathMax(d2, tp2m * H);
      if(tp3m > 0.0)
         d3 = MathMax(d3, tp3m * H);
     }
   else
     {
      d2 = MathMax(d2, InpTp2R * R);
      d3 = MathMax(d3, InpTp3R * R);
     }
   d3 = MathMax(d3, d2 + 0.2 * R);
   g_levels.tp2 = g_levels.entry + dir * d2;
   g_levels.tp3 = g_levels.entry + dir * d3;
   g_levels.tp_hit = 0;
  }

string B100LevelsText(void)
  {
   if(!g_levels.valid)
      return "entry —   SL —   TP1 —   TP2 —   TP3 —";
   return
      "entry " + DoubleToString(g_levels.entry, _Digits) +
      "   SL " + DoubleToString(g_levels.sl, _Digits) +
      "   TP1 " + DoubleToString(g_levels.tp1, _Digits) +
      "   TP2 " + DoubleToString(g_levels.tp2, _Digits) +
      "   TP3 " + DoubleToString(g_levels.tp3, _Digits) +
      "   (1R=" + DoubleToString(g_levels.r, _Digits) + ")";
  }

void B100ShadowStep(const double bid, const double ask, const string labeled)
  {
   B100ShadowMark(g_shadow, bid, ask);
   if(g_shadow.open && g_levels.valid)
     {
      const double px = (g_shadow.dir > 0) ? bid : ask;
      const bool hit3 = (g_shadow.dir > 0 && px >= g_levels.tp3) || (g_shadow.dir < 0 && px <= g_levels.tp3);
      const bool hit2 = (g_shadow.dir > 0 && px >= g_levels.tp2) || (g_shadow.dir < 0 && px <= g_levels.tp2);
      const bool hit1 = (g_shadow.dir > 0 && px >= g_levels.tp1) || (g_shadow.dir < 0 && px <= g_levels.tp1);
      if(hit3)
        {
         g_levels.tp_hit = 3;
         B100ShadowClose(g_shadow, px, "CLOSE_TP");
         Print("SHADOW TP3 hit — virtual close ", DoubleToString(px, _Digits));
         return;
        }
      if(hit2 && g_levels.tp_hit < 2)
        {
         g_levels.tp_hit = 2;
         Print("SHADOW TP2 hit ", DoubleToString(px, _Digits));
        }
      else if(hit1 && g_levels.tp_hit < 1)
        {
         g_levels.tp_hit = 1;
         Print("SHADOW TP1 hit ", DoubleToString(px, _Digits));
        }
     }
   if(g_risk_code != "RISK_GATE_PASSED")
      return;
   if(g_shadow.open)
     {
      if(labeled == "BOUNCE" || labeled == "CENSORED_OR_AMBIGUOUS")
         B100ShadowClose(g_shadow, 0.5 * (bid + ask), "CLOSE_INVALIDATE");
      return;
     }
   if(g_decision.hypothetical == B100_NO_TRADE)
      return;
   if(labeled != "BREAKOUT_UP" && labeled != "BREAKOUT_DOWN")
      return;

   const int dir = (g_decision.hypothetical == B100_ENTER_LONG) ? 1 : -1;
   if(labeled == "BREAKOUT_UP" && dir < 0)
      return;
   if(labeled == "BREAKOUT_DOWN" && dir > 0)
      return;

   const double entry = (dir > 0) ? ask : bid;
   if(InpStrategy == B100_STRAT_BOX_M30)
      B100FillBoxLevels(dir, entry, ask, bid);
   else
      B100FillLevels(dir, entry, ask, bid);
   if(!g_levels.valid)
      return;
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double lots = B100StopRiskLots(equity, InpRiskFraction, g_levels.entry, g_levels.sl);
   if(lots <= 0.0)
      return;
   B100ShadowOpen(g_shadow, dir, g_levels.entry, g_levels.sl, lots);
   Print("SHADOW virtual ", (dir > 0 ? "LONG" : "SHORT"),
         " lots=", DoubleToString(lots, 2),
         " entry=", DoubleToString(g_levels.entry, _Digits),
         " SL=", DoubleToString(g_levels.sl, _Digits),
         " TP1=", DoubleToString(g_levels.tp1, _Digits),
         " TP2=", DoubleToString(g_levels.tp2, _Digits),
         " TP3=", DoubleToString(g_levels.tp3, _Digits));
  }

void B100ComputeSignal(const string labeled, const bool shadow_was_open, const bool shadow_closed, const double bid, const double ask)
  {
   const double mid = 0.5 * (bid + ask);
   string next = g_signal;
   string note = g_signal_note;
   const bool box_mode = (InpStrategy == B100_STRAT_BOX_M30);
   bool blocked = false;

   if(box_mode && !g_box.ready && !g_fib.on && !(g_episode.active && g_episode.tracking))
     {
      next = "WAIT";
      note = "M30 box warming — need prior closed bars";
      g_levels.valid = false;
      blocked = true;
     }
   else if(!box_mode && !g_pipe.warmed)
     {
      next = "WAIT";
      note = "warmup — wait for ~12 ticks, width settles ~160";
      g_levels.valid = false;
      blocked = true;
     }

   if(blocked)
     { }
   else if(g_shadow.open)
     {
      next = "HOLD";
      note = (g_shadow.dir > 0 ? "virtual LONG" : "virtual SHORT");
      if(g_levels.tp_hit == 1)
         note += " — TP1 done, runner to TP2/TP3";
      else if(g_levels.tp_hit == 2)
         note += " — TP2 done, runner to TP3";
      else
         note += " — EXIT at SL, bounce, or TP3";
     }
   else if(shadow_closed)
     {
      next = "EXIT";
      if(g_levels.tp_hit >= 3)
         note = "TP3 hit — full target";
      else if(labeled != "")
         note = labeled;
      else
         note = "shadow stop / close";
      g_signal_seq = g_pipe.seq;
     }
   else if(labeled == "BREAKOUT_UP")
     {
      if(box_mode)
         B100FillBoxLevels(1, ask, ask, bid);
      else
         B100FillLevels(1, ask, ask, bid);
      if(box_mode && g_risk_code == "RISK_GATE_PASSED")
        {
         next = "BUY";
         note = "BUY STOP filled — pause high taken, Observe only (no OrderSend)";
        }
      else if(!box_mode && g_decision.hypothetical == B100_ENTER_LONG && g_decision.safe_ev > 0.0 && g_risk_code == "RISK_GATE_PASSED")
        {
         next = "BUY";
         note = "BREAKOUT_UP + SafeEV>0 — Observe only";
        }
      else
        {
         next = "STAND_DOWN";
         note = "BREAKOUT_UP but " + (box_mode ? g_risk_code : g_decision.reason);
        }
      g_signal_seq = g_pipe.seq;
      if(box_mode)
         B100MarkBoxSignal(1, (g_levels.valid ? g_levels.entry : mid));
      else
         B100MarkEvent(labeled, mid);
     }
   else if(labeled == "BREAKOUT_DOWN")
     {
      if(box_mode)
         B100FillBoxLevels(-1, bid, ask, bid);
      else
         B100FillLevels(-1, bid, ask, bid);
      if(box_mode && g_risk_code == "RISK_GATE_PASSED")
        {
         next = "SELL";
         note = "SELL STOP filled — pause low taken, Observe only (no OrderSend)";
        }
      else if(!box_mode && g_decision.hypothetical == B100_ENTER_SHORT && g_decision.safe_ev > 0.0 && g_risk_code == "RISK_GATE_PASSED")
        {
         next = "SELL";
         note = "BREAKOUT_DOWN + SafeEV>0 — Observe only";
        }
      else
        {
         next = "STAND_DOWN";
         note = "BREAKOUT_DOWN but " + (box_mode ? g_risk_code : g_decision.reason);
        }
      g_signal_seq = g_pipe.seq;
      if(box_mode)
         B100MarkBoxSignal(-1, (g_levels.valid ? g_levels.entry : mid));
      else
         B100MarkEvent(labeled, mid);
     }
   else if(labeled == "BOUNCE" || labeled == "CENSORED_OR_AMBIGUOUS")
     {
      next = (shadow_was_open || g_last_alert == "HOLD") ? "EXIT" : "WAIT";
      note = box_mode ? (labeled + " — failed box break, no fade") : (labeled + " — no entry");
      g_signal_seq = g_pipe.seq;
      B100MarkEvent(labeled, mid);
     }
   else if(!box_mode && g_pipe.pending.active)
     {
      next = "WATCH";
      note = (g_pipe.pending.side > 0)
             ? "upper touch — waiting for BUY breakout or bounce EXIT"
             : "lower touch — waiting for SELL breakout or bounce EXIT";
     }
   else if((g_pipe.seq - g_signal_seq) > InpLabelHorizon &&
           (g_signal == "BUY" || g_signal == "SELL" || g_signal == "EXIT" || g_signal == "STAND_DOWN"))
     {
      next = "WAIT";
      note = "last setup expired — looking for the next touch";
      g_levels.valid = false;
     }

   const bool changed = (next != g_signal);
   g_signal = next;
   g_signal_note = note;
   if(changed && InpAlerts && (next == "BUY" || next == "SELL" || next == "EXIT"))
     {
      string msg = "BREAK100 " + next + "  " + _Symbol + "  " + note;
      if(g_levels.valid)
         msg += "  " + B100LevelsText();
      Alert(msg);
      Print("SIGNAL ", next, "  ", note, "  ", B100LevelsText());
      g_last_alert = next;
     }
  }

void B100MarkEvent(const string labeled, const double price)
  {
   if(!InpDrawArrows)
      return;
   const string name = "B100_ev_" + IntegerToString(g_pipe.seq);
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price);
   int code = 159;
   color clr = clrSilver;
   if(labeled == "BREAKOUT_UP")
     {
      code = 233;
      clr = C'111,154,125';
     }
   else if(labeled == "BREAKOUT_DOWN")
     {
      code = 234;
      clr = C'181,106,92';
     }
   else if(labeled == "BOUNCE")
     {
      code = 251;
      clr = C'196,164,92';
     }
   else
     {
      code = 158;
      clr = C'139,144,160';
     }
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   labeled + " / SIGNAL " + g_signal + " / " + B100LevelsText());
  }

void B100CreateLines()
  {
   if(!InpDrawChannel)
      return;
   B100HLine(LINE_MID, CLR_EQ,  STYLE_DOT);
   B100HLine(LINE_UP,  CLR_RES, STYLE_SOLID);
   B100HLine(LINE_DN,  CLR_SUP, STYLE_SOLID);
  }

void B100HLine(const string name, const color clr, const ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void B100HideLevels(void)
  {
   ObjectSetInteger(0, LV_ENTRY, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_SL,    OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_TP1,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_TP2,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_TP3,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_ENTRY_L, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_SL_L,    OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_TP1_L,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_TP2_L,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_TP3_L,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, LV_FIBO, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
  }

void B100FibClear(void)
  {
   g_fib.on  = false;
   g_fib.dir = 0;
   g_fib.entry = 0;
   g_fib.sl = 0;
   g_levels.valid = false;
   B100HideLevels();
  }

void B100FibLatch(const int dir, const double entry, const double sl, const double tp1, const double tp2, const double tp3)
  {
   if(dir == 0 || entry <= 0.0 || sl <= 0.0)
      return;
   const bool fresh = (!g_fib.on || g_fib.dir != dir ||
                       MathAbs(g_fib.entry - entry) > _Point ||
                       MathAbs(g_fib.sl - sl) > _Point);
   g_fib.on    = true;
   g_fib.dir   = dir;
   g_fib.entry = entry;
   g_fib.sl    = sl;
   g_fib.tp1   = tp1;
   g_fib.tp2   = tp2;
   g_fib.tp3   = tp3;
   if(g_fib.t0 == 0 || fresh)
     {
      g_fib.t0 = (g_box.t_left > 0) ? g_box.t_left : iTime(_Symbol, PERIOD_M30, 1);
      if(g_fib.t0 == 0)
         g_fib.t0 = TimeCurrent();
      g_fib.t1 = TimeCurrent();
      if(g_fib.t1 <= g_fib.t0)
         g_fib.t1 = g_fib.t0 + PeriodSeconds(PERIOD_M30);
     }
   if(fresh)
      Print("B100 levels  ", (dir > 0 ? "BUY" : "SELL"),
            "  ENTRY ", DoubleToString(entry, _Digits),
            "  SL ", DoubleToString(sl, _Digits),
            "  TP1 ", DoubleToString(tp1, _Digits),
            "  TP2 ", DoubleToString(tp2, _Digits),
            "  TP3 ", DoubleToString(tp3, _Digits));
  }

void B100LevelRay(const string name, const datetime t0, const datetime t1, const double price, const color clr, const string caption)
  {
   if(price <= 0.0)
     {
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
     }
   if(ObjectFind(0, name) >= 0 &&
      (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_TREND)
      ObjectDelete(0, name);
   datetime ta = t0;
   datetime tb = t1;
   if(ta == 0)
      ta = TimeCurrent() - 4 * PeriodSeconds(PERIOD_CURRENT);
   if(tb <= ta)
      tb = ta + PeriodSeconds(PERIOD_CURRENT);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, ta, price, tb, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, ta);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, tb);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, caption + " " + DoubleToString(price, _Digits));
  }

void B100LevelTag(const string name, const datetime t, const double price, const string text, const color clr)
  {
   if(price <= 0.0 || text == "")
     {
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
     }
   if(ObjectFind(0, name) >= 0 &&
      (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_TEXT)
      ObjectDelete(0, name);
   datetime tx = t;
   if(tx == 0)
      tx = TimeCurrent();
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, tx, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, tx);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
  }

void B100PaintOneLevel(const string ray, const string tag, const datetime t0, const datetime t1, const datetime tx,
                       const double price, const string label, const color clr)
  {
   B100LevelRay(ray, t0, t1, price, clr, label);
   if(price > 0.0)
      B100LevelTag(tag, tx, price, label + "  " + DoubleToString(price, _Digits), clr);
  }

void B100PaintLevels()
  {
   ObjectDelete(0, LV_FIBO);
   if(!InpDrawLevels)
     {
      B100HideLevels();
      return;
     }
   double en = 0, sl = 0, p1 = 0, p2 = 0, p3 = 0;
   datetime ta = 0;
   bool path = false;
   if(g_fib.on && g_fib.entry > 0.0 && g_fib.sl > 0.0)
     {
      path = true;
      en = g_fib.entry;
      sl = g_fib.sl;
      p1 = g_fib.tp1;
      p2 = g_fib.tp2;
      p3 = g_fib.tp3;
      ta = g_fib.t0;
     }
   else if(g_episode.tracking && g_episode.entry > 0.0)
     {
      path = true;
      en = g_episode.entry;
      sl = g_episode.sl;
      p1 = g_episode.tp1;
      p2 = g_episode.tp2;
      p3 = g_episode.tp3;
     }
   else if(g_levels.valid &&
           (g_signal == "BUY" || g_signal == "SELL" || g_signal == "HOLD"))
     {
      path = true;
      en = g_levels.entry;
      sl = g_levels.sl;
      p1 = g_levels.tp1;
      p2 = g_levels.tp2;
      p3 = g_levels.tp3;
     }
   if(!path)
     {
      B100HideLevels();
      return;
     }
   if(ta == 0)
      ta = iTime(_Symbol, PERIOD_CURRENT, 4);
   if(ta == 0)
      ta = TimeCurrent() - 4 * PeriodSeconds(PERIOD_CURRENT);
   datetime tb = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(tb <= ta)
      tb = ta + PeriodSeconds(PERIOD_CURRENT);
   const datetime tx = tb + PeriodSeconds(PERIOD_CURRENT);

   B100PaintOneLevel(LV_ENTRY, LV_ENTRY_L, ta, tb, tx, en, "ENTRY", clrSilver);
   B100PaintOneLevel(LV_SL,    LV_SL_L,    ta, tb, tx, sl, "SL",    CLR_ARR_SELL);
   B100PaintOneLevel(LV_TP1,   LV_TP1_L,   ta, tb, tx, p1, "TP1",   CLR_ARR_BUY);
   B100PaintOneLevel(LV_TP2,   LV_TP2_L,   ta, tb, tx, p2, "TP2",   C'40,180,140');
   B100PaintOneLevel(LV_TP3,   LV_TP3_L,   ta, tb, tx, p3, "TP3",   C'30,140,110');
   ChartRedraw(0);
  }

void B100PaintHistBoxes()
  {
   ObjectsDeleteAll(0, "B100_hx_");
   for(int i = 0; i < g_box.hist_n; i++)
     {
      const string id = "B100_hx_" + IntegerToString(i);
      ObjectCreate(0, id, OBJ_RECTANGLE, 0,
                   g_box.hist[i].t_left, g_box.hist[i].high,
                   g_box.hist[i].t_right + PeriodSeconds(InpBoxTF), g_box.hist[i].low);
      ObjectSetInteger(0, id, OBJPROP_COLOR, CLR_BOX_FILL);
      ObjectSetInteger(0, id, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, id, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, id, OBJPROP_BACK, true);
      ObjectSetInteger(0, id, OBJPROP_FILL, true);
      ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, id, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M30);
     }
  }

void B100BoxRail(const string name, const datetime t0, const datetime t1, const double price, const color clr, const int width)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t0);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M30);
  }

void B100BoxTag(const string name, const datetime t, const double price, const string text, const color clr, const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Georgia");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M30);
  }

void B100HideWatchMarks()
  {
   ObjectSetInteger(0, BOX_ARR_BUY,  OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, BOX_ARR_SELL, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, BOX_WATCH_L,  OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
  }

void B100WatchGlyph(const string name, const datetime t, const double price,
                    const int code, const color clr, const ENUM_ANCHOR_POINT anc, const string tip)
  {
   if(t == 0 || price <= 0.0)
     {
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
     }
   if(ObjectFind(0, name) >= 0 &&
      (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_TEXT)
      ObjectDelete(0, name);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetString(0, name, OBJPROP_FONT, "Wingdings");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, B100_ARROW_FS);
   ObjectSetString(0, name, OBJPROP_TEXT, CharToString((uchar)code));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M30);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
  }

void B100PaintBox()
  {
   // Trigger on n_boxes (uncapped, increments on every single arm), not
   // hist_n. hist_n is the ring-buffer fill level in B100BoxPushHist — it
   // counts up only until it reaches B100_BOX_HIST (24) and then stays pinned
   // there forever, even though the ring keeps rotating and its *contents*
   // keep changing underneath. Comparing against hist_n meant the on-chart
   // history boxes silently froze the moment the 24th box ever formed: every
   // box after that kept arming, alerting and trading correctly, but its
   // rectangle was never painted, because this trigger had already gone
   // permanently false.
   static int last_n_boxes = -1;
   if(g_box.n_boxes != last_n_boxes)
     {
      B100PaintHistBoxes();
      last_n_boxes = g_box.n_boxes;
     }
   if(InpStrategy != B100_STRAT_BOX_M30)
     {
      B100HideWatchMarks();
      return;
     }
   // Keep the last zone on the chart after fill (SCAN). Hide only if we never had a box.
   if(g_box.t_left == 0 || g_box.high == 0.0 || g_box.low == 0.0)
     {
      B100HideWatchMarks();
      return;
     }
   const datetime t1 = (g_box.t_right > 0) ? g_box.t_right + PeriodSeconds(PERIOD_M30) : TimeCurrent();
   const datetime t0 = (g_box.t_left > 0) ? g_box.t_left : iTime(_Symbol, PERIOD_M30, 4);
   if(ObjectFind(0, BOX_RECT) < 0)
      ObjectCreate(0, BOX_RECT, OBJ_RECTANGLE, 0, t0, g_box.high, t1, g_box.low);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_TIME, 0, t0);
   ObjectSetDouble(0, BOX_RECT, OBJPROP_PRICE, 0, g_box.high);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_TIME, 1, t1);
   ObjectSetDouble(0, BOX_RECT, OBJPROP_PRICE, 1, g_box.low);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_COLOR, CLR_BOX_FILL);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_BACK, true);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_FILL, true);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, BOX_RECT, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M30);

   B100BoxRail(BOX_RES, t0, t1, g_box.high, CLR_RES, 2);
   B100BoxRail(BOX_SUP, t0, t1, g_box.low,  CLR_SUP, 2);
   B100BoxRail(BOX_MID, t0, t1, 0.5 * (g_box.high + g_box.low), CLR_EQ, 1);
   if(g_box.state == B100_BOX_ARMED)
     {
      B100BoxRail(BOX_BUY,  t0, t1, g_box.buy_stop,  CLR_BUY,  2);
      B100BoxRail(BOX_SELL, t0, t1, g_box.sell_stop, CLR_SELL, 2);
      if(InpDrawArrows)
        {
         B100WatchGlyph(BOX_ARR_BUY,  t1, g_box.buy_stop,  233, CLR_ARR_BUY,  ANCHOR_LOWER,
                        "WATCH BUY STOP  (not a fill)");
         B100WatchGlyph(BOX_ARR_SELL, t1, g_box.sell_stop, 234, CLR_ARR_SELL, ANCHOR_UPPER,
                        "WATCH SELL STOP  (not a fill)");
         B100BoxTag(BOX_WATCH_L, t1, 0.5 * (g_box.high + g_box.low), "WATCH", C'184,179,168', ANCHOR_LEFT);
        }
      else
         B100HideWatchMarks();
     }
   else
     {
      ObjectSetInteger(0, BOX_BUY,  OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_SELL, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      B100HideWatchMarks();
     }
   B100BoxTag(BOX_RES_LBL, t0, g_box.high, "RES", CLR_RES, ANCHOR_LEFT_LOWER);
   B100BoxTag(BOX_SUP_LBL, t0, g_box.low,  "SUP", CLR_SUP, ANCHOR_LEFT_UPPER);
  }

void B100UpdateLines()
  {
   if(!InpDrawChannel || InpStrategy == B100_STRAT_BOX_M30)
      return;
   ObjectSetDouble(0, LINE_MID, OBJPROP_PRICE, g_pipe.kalman_x);
   ObjectSetDouble(0, LINE_UP,  OBJPROP_PRICE, g_pipe.kalman_x + g_pipe.half_width);
   ObjectSetDouble(0, LINE_DN,  OBJPROP_PRICE, g_pipe.kalman_x - g_pipe.half_width);
  }

void B100ApplyChartSkin()
  {
   if(g_skin_on)
      return;
   g_old_bg   = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   g_old_fg   = (color)ChartGetInteger(0, CHART_COLOR_FOREGROUND);
   g_old_grid = (color)ChartGetInteger(0, CHART_COLOR_GRID);
   g_old_up   = (color)ChartGetInteger(0, CHART_COLOR_CHART_UP);
   g_old_dn   = (color)ChartGetInteger(0, CHART_COLOR_CHART_DOWN);
   g_old_bull = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
   g_old_bear = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR);
   g_old_ask  = (color)ChartGetInteger(0, CHART_COLOR_ASK);
   g_old_bid  = (color)ChartGetInteger(0, CHART_COLOR_BID);
   g_old_vol  = (color)ChartGetInteger(0, CHART_COLOR_VOLUME);
   g_old_show_grid = (bool)ChartGetInteger(0, CHART_SHOW_GRID);
   g_old_show_vol  = (ChartGetInteger(0, CHART_SHOW_VOLUMES) != CHART_VOLUME_HIDE);
   g_old_show_ohlc = (bool)ChartGetInteger(0, CHART_SHOW_OHLC);
   g_old_show_ask  = (bool)ChartGetInteger(0, CHART_SHOW_ASK_LINE);
   g_skin_on = true;
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, CHART_VOLUME_HIDE);
   ChartSetInteger(0, CHART_SHOW_OHLC, false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, true);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, CLR_INK);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'184,179,168');
   ChartSetInteger(0, CHART_COLOR_GRID, C'22,26,34');
   ChartSetInteger(0, CHART_COLOR_CHART_UP, CLR_RES);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, CLR_SELL);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, CLR_RES);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, CLR_SELL);
   ChartSetInteger(0, CHART_COLOR_BID, CLR_SUP);
   ChartSetInteger(0, CHART_COLOR_ASK, CLR_RES);
   ChartSetInteger(0, CHART_COLOR_VOLUME, C'48,54,64');
   ChartRedraw(0);
  }

void B100RestoreChartSkin()
  {
   if(!g_skin_on)
      return;
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, g_old_bg);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, g_old_fg);
   ChartSetInteger(0, CHART_COLOR_GRID, g_old_grid);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, g_old_up);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, g_old_dn);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, g_old_bull);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, g_old_bear);
   ChartSetInteger(0, CHART_COLOR_ASK, g_old_ask);
   ChartSetInteger(0, CHART_COLOR_BID, g_old_bid);
   ChartSetInteger(0, CHART_COLOR_VOLUME, g_old_vol);
   ChartSetInteger(0, CHART_SHOW_GRID, g_old_show_grid);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, g_old_show_vol ? CHART_VOLUME_TICK : CHART_VOLUME_HIDE);
   ChartSetInteger(0, CHART_SHOW_OHLC, g_old_show_ohlc);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, g_old_show_ask);
   g_skin_on = false;
   ChartRedraw(0);
  }

void B100ReplayJournalMarks()
  {
   if(!InpDrawArrows)
      return;
   string key = _Symbol;
   StringReplace(key, " ", "_");
   const int fh = FileOpen("BREAK100_outcome_" + key + ".csv",
                           FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
      return;
   for(int i = 0; i < 6; i++)
      FileReadString(fh);
   datetime last_armed = 0;
   while(!FileIsEnding(fh))
     {
      const datetime armed = (datetime)FileReadNumber(fh);
      FileReadString(fh);
      const string label = FileReadString(fh);
      FileReadNumber(fh);
      const double bid = FileReadNumber(fh);
      const double ask = FileReadNumber(fh);
      if(armed == 0 || armed == last_armed)
         continue;
      last_armed = armed;
      if(label == "BREAKOUT_UP")
         B100MarkBoxSignal(1, ask, armed);
      else if(label == "BREAKOUT_DOWN")
         B100MarkBoxSignal(-1, bid, armed);
     }
   FileClose(fh);
  }

void B100MarkBoxSignal(const int dir, const double price, datetime when)
  {
   if(!InpDrawArrows)
      return;
   const datetime t = (when > 0) ? when : TimeCurrent();
   const int step = PeriodSeconds(PERIOD_M30);
   const datetime t0 = t - step;
   const string id = IntegerToString((int)(when > 0 ? when : (g_box.armed_bar > 0 ? g_box.armed_bar : t)));
   const string arr = "B100_jn_arr_" + id;
   const string ln  = "B100_jn_ln_" + id;
   const color clr = (dir > 0) ? CLR_ARR_BUY : CLR_ARR_SELL;
   const string glyph = CharToString((uchar)((dir > 0) ? 233 : 234));

   if(ObjectFind(0, arr) >= 0)
      ObjectDelete(0, arr);
   ObjectCreate(0, arr, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, arr, OBJPROP_FONT, "Wingdings");
   ObjectSetInteger(0, arr, OBJPROP_FONTSIZE, B100_ARROW_FS);
   ObjectSetString(0, arr, OBJPROP_TEXT, glyph);
   ObjectSetInteger(0, arr, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, arr, OBJPROP_ANCHOR, (dir > 0) ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, arr, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, arr, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, arr, OBJPROP_BACK, false);
   ObjectSetInteger(0, arr, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, arr, OBJPROP_TOOLTIP,
                   (dir > 0 ? "BUY " : "SELL ") + TimeToString(t, TIME_DATE | TIME_MINUTES) +
                   "  " + DoubleToString(price, _Digits));

   if(ObjectFind(0, ln) >= 0)
      ObjectDelete(0, ln);
   ObjectCreate(0, ln, OBJ_TREND, 0, t0, price, t, price);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, ln, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ln, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, ln, OBJPROP_BACK, false);
   ObjectSetInteger(0, ln, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   Print("B100 arrow ", (dir > 0 ? "BUY" : "SELL"),
         "  ", TimeToString(t, TIME_DATE | TIME_MINUTES),
         "  ", DoubleToString(price, _Digits),
         "  fs=", B100_ARROW_FS);
   ChartRedraw(0);
  }

int B100JournalWidth()
  {
   int scale = (int)ChartGetInteger(0, CHART_SCALE);
   if(scale < 0) scale = 0;
   if(scale > 5) scale = 5;
   return 1;
  }

void B100RescaleJournalMarks()
  {
   const int n = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < n; i++)
     {
      const string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, "B100_jn_arr_") == 0)
        {
         if((ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_TEXT)
            continue;
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, B100_ARROW_FS);
        }
      else if(StringFind(name, "B100_jn_ln_") == 0)
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
     }
   ChartRedraw(0);
  }

// Every gate that must agree before the button can arm anything. Returned as a
// reason string so the chart can say exactly which one is blocking.
bool B100LiveGatesOk(string &why)
  {
   if(!InpAllowLiveTrading)
     {
      why = "InpAllowLiveTrading is false";
      return false;
     }
   if(!B100IsRealAccount())
     {
      why = "not a real account";
      return false;
     }
   if(InpLiveAccountLogin == 0 || InpLiveAccountLogin != AccountInfoInteger(ACCOUNT_LOGIN))
     {
      why = "login " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " not allowlisted";
      return false;
     }
   if(g_mode.mode != B100_LIVE)
     {
      why = "mode is " + B100ModeName(g_mode.mode);
      return false;
     }
   if(g_mode.health != B100_HEALTHY)
     {
      why = "health fault: " + g_mode.block_reason;
      return false;
     }
   why = "";
   return true;
  }

void B100LiveButtonCreate(void)
  {
   if(!InpShowLiveButton)
      return;
   if(ObjectFind(0, BTN_LIVE) < 0)
      ObjectCreate(0, BTN_LIVE, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_YDISTANCE, 44);   // placeholder; B100LiveButtonPaint() repositions using g_dash_bottom_y below
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_XSIZE, 168);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_YSIZE, 26);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, BTN_LIVE, OBJPROP_FONT, "Segoe UI Semibold");

   if(ObjectFind(0, BTN_ENTER) < 0)
      ObjectCreate(0, BTN_ENTER, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_YDISTANCE, 76);   // placeholder; B100EnterButtonPaint() repositions using g_dash_bottom_y below
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_XSIZE, 168);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_YSIZE, 26);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, BTN_ENTER, OBJPROP_FONT, "Segoe UI Semibold");

   B100LiveButtonPaint();
   B100EnterButtonPaint();
  }

// One-shot ground truth for the Experts tab, not a guess. Logs whether
// BTN_LIVE/BTN_ENTER actually exist and exactly where/what color/what text
// they carry (InpShowLiveButton=false would explain "buttons never appear" on
// its own — this makes that visible instead of assumed), plus every chart
// object whose name contains "Label", since MT5's own naming convention for a
// repeated default-named insert is "Label", "Label 1", "Label 2", ... which an
// exact match on "Label" alone would miss.
void B100LogObjectDiagnostics(void)
  {
   Print("B100 DIAG  InpShowLiveButton=", InpShowLiveButton,
         "  g_dash_bottom_y=", g_dash_bottom_y);
   string names[2] = {BTN_LIVE, BTN_ENTER};
   for(int i = 0; i < 2; i++)
     {
      const string nm = names[i];
      if(ObjectFind(0, nm) < 0)
        {
         Print("B100 DIAG  '", nm, "'  NOT FOUND");
         continue;
        }
      Print("B100 DIAG  '", nm, "'  corner=", ObjectGetInteger(0, nm, OBJPROP_CORNER),
            "  x=", ObjectGetInteger(0, nm, OBJPROP_XDISTANCE),
            "  y=", ObjectGetInteger(0, nm, OBJPROP_YDISTANCE),
            "  xsize=", ObjectGetInteger(0, nm, OBJPROP_XSIZE),
            "  ysize=", ObjectGetInteger(0, nm, OBJPROP_YSIZE),
            "  bg=", ColorToString((color)ObjectGetInteger(0, nm, OBJPROP_BGCOLOR)),
            "  fg=", ColorToString((color)ObjectGetInteger(0, nm, OBJPROP_COLOR)),
            "  text='", ObjectGetString(0, nm, OBJPROP_TEXT), "'",
            "  timeframes=", ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES));
     }

   const int total = ObjectsTotal(0, -1, -1);
   int label_hits = 0;
   for(int i = 0; i < total; i++)
     {
      const string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, "Label") < 0)
         continue;
      label_hits++;
      Print("B100 DIAG  Label-object '", nm, "'  type=",
            EnumToString((ENUM_OBJECT)ObjectGetInteger(0, nm, OBJPROP_TYPE)),
            "  corner=", ObjectGetInteger(0, nm, OBJPROP_CORNER),
            "  x=", ObjectGetInteger(0, nm, OBJPROP_XDISTANCE),
            "  y=", ObjectGetInteger(0, nm, OBJPROP_YDISTANCE),
            "  text='", ObjectGetString(0, nm, OBJPROP_TEXT), "'");
     }
   Print("B100 DIAG  total chart objects=", total, "  matching 'Label'=", label_hits);
  }

// Manual one-click entry. Deliberately reports WHY it is unavailable rather than
// sitting inert: an armed box that cannot be traded is the interesting case.
void B100EnterButtonPaint(void)
  {
   if(!InpShowLiveButton || ObjectFind(0, BTN_ENTER) < 0)
      return;
   // Stacks directly under BTN_LIVE, which itself now floats below the
   // dashboard, so the two buttons and the dashboard can never overlap.
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_YDISTANCE, g_dash_bottom_y + 26 + 6);
   const bool have_box = (g_box.ready && g_box.state == B100_BOX_ARMED);
   const bool can_send = B100BrokerOrderIntentPermitted(g_mode);
   string text;
   color bg, fg;
   if(!have_box)
     {
      text = "no box armed";
      bg   = C'40,42,50'; fg = C'150,152,160';
     }
   else if(!can_send)
     {
      text = "ENTER (needs DEMO/LIVE)";
      bg   = C'40,42,50'; fg = C'150,152,160';
     }
   else if(g_oco_armed)
     {
      text = "orders already placed";
      bg   = C'44,58,76'; fg = C'160,180,200';
     }
   else
     {
      text = "▸ ENTER THIS BOX";
      bg   = C'46,110,86'; fg = clrWhite;
     }
   ObjectSetString(0, BTN_ENTER, OBJPROP_TEXT, text);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, BTN_ENTER, OBJPROP_STATE, false);
   ObjectSetString(0, BTN_ENTER, OBJPROP_TOOLTIP,
                   "Place this box's four legs now, bypassing the size filter. "
                   "All broker and risk checks still apply.");
  }

void B100LiveButtonPaint(void)
  {
   if(!InpShowLiveButton || ObjectFind(0, BTN_LIVE) < 0)
      return;
   // Anchor below the dashboard's actual bottom edge, not a fixed Y — a fixed
   // Y is what let the dashboard grow tall enough to paint over this button.
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_YDISTANCE, g_dash_bottom_y);
   string why = "";
   const bool gates = B100LiveGatesOk(why);
   string text;
   color bg, fg;
   if(!gates)
     {
      text = "LIVE LOCKED";
      bg   = C'40,42,50';
      fg   = C'150,152,160';
     }
   else if(g_mode.live_armed)
     {
      text = "● LIVE ARMED — REAL MONEY";
      bg   = C'190,40,40';
      fg   = clrWhite;
     }
   else
     {
      text = "LIVE OFF — click to arm";
      bg   = C'52,90,72';
      fg   = C'220,235,225';
     }
   ObjectSetString(0, BTN_LIVE, OBJPROP_TEXT, text);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, BTN_LIVE, OBJPROP_STATE, false);
   ObjectSetString(0, BTN_LIVE, OBJPROP_TOOLTIP,
                   gates ? "Toggles real-money order placement for this chart"
                         : "Blocked: " + why);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_LIVE)
     {
      string why = "";
      if(!B100LiveGatesOk(why))
        {
         Print("B100 LIVE arm refused — ", why);
         g_mode.live_armed = false;
        }
      else
        {
         g_mode.live_armed = !g_mode.live_armed;
         Print("B100 LIVE ", (g_mode.live_armed ? "ARMED — real orders enabled" : "disarmed"),
               "  account=", AccountInfoInteger(ACCOUNT_LOGIN), "  symbol=", _Symbol);
         if(g_mode.live_armed)
            B100Tg("LIVE ARMED on " + _Symbol + " account " +
                   IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
         else
            B100CancelBoxOco("live disarmed");
        }
      B100LiveButtonPaint();
      ChartRedraw();
      return;
     }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_ENTER)
     {
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!g_box.ready || g_box.state != B100_BOX_ARMED)
         Print("B100 manual entry — no box armed");
      else if(!B100BrokerOrderIntentPermitted(g_mode))
         Print("B100 manual entry refused — mode=", B100ModeName(g_mode.mode),
               " (needs DEMO, or LIVE armed on the allowlisted real account)");
      else
        {
         // Operator intent overrides the statistical size filter, but never the
         // broker or risk gates — those still run inside B100ArmBoxOco.
         Print("B100 manual entry requested — bypassing the size filter only");
         g_manual_entry_override = true;
         B100ArmBoxOco(bid, ask);
         g_manual_entry_override = false;
         if(g_oco_armed)
            B100ShadowSetDecision(g_shadow, "MANUAL_BUTTON");
        }
      B100EnterButtonPaint();
      ChartRedraw();
      return;
     }
   if(id == CHARTEVENT_CHART_CHANGE)
      B100RescaleJournalMarks();
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_CHANGE ||
      id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_DELETE ||
      id == CHARTEVENT_OBJECT_ENDEDIT)
      B100HarvestHumanBoxes();
  }

bool B100IsEaRect(const string name)
  {
   if(StringFind(name, "B100_") == 0)
      return true;
   if(StringFind(name, "B100") == 0 && StringFind(name, "B100H") != 0)
      return true;
   return false;
  }

void B100HarvestHumanBoxes()
  {
   if(!InpHarvestRects)
      return;
   static bool s_busy = false;
   if(s_busy)
      return;
   s_busy = true;
   string sym = _Symbol;
   StringReplace(sym, " ", "_");
   const int fh = FileOpen("BREAK100_human_box_" + sym + ".csv",
                           FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
     {
      s_busy = false;
      return;
     }
   FileWrite(fh, "name", "t_left", "t_right", "high", "low", "bars", "height", "h_vs_h4", "overlap_ea",
            "after_dir", "after_bars", "after_size", "after_vs_box");
   ObjectsDeleteAll(0, "B100H_ok_");
   int kept = 0, n_up = 0, n_dn = 0;
   const int n = ObjectsTotal(0, 0, OBJ_RECTANGLE);
   for(int i = 0; i < n; i++)
     {
      const string name = ObjectName(0, i, 0, OBJ_RECTANGLE);
      if(name == "" || B100IsEaRect(name))
         continue;
      datetime t0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
      double p0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
      if(t0 == 0 || t1 == 0)
         continue;
      if(t1 < t0)
        {
         datetime tmp = t0;
         t0 = t1;
         t1 = tmp;
        }
      double hi = MathMax(p0, p1);
      double lo = MathMin(p0, p1);
      int shL = iBarShift(_Symbol, PERIOD_M30, t0, true);
      int shR = iBarShift(_Symbol, PERIOD_M30, t1, true);
      int nb = 0;
      if(shL >= 0 && shR >= 0)
        {
         nb = MathAbs(shL - shR) + 1;
         const int a = MathMax(shL, shR);
         const int z = MathMin(shL, shR);
         double whi = iHigh(_Symbol, PERIOD_M30, z);
         double wlo = iLow(_Symbol, PERIOD_M30, z);
         for(int s = z; s <= a; s++)
           {
            const double hh = iHigh(_Symbol, PERIOD_M30, s);
            const double ll = iLow(_Symbol, PERIOD_M30, s);
            if(hh > whi) whi = hh;
            if(ll < wlo) wlo = ll;
           }
         if(whi > wlo)
           {
            hi = whi;
            lo = wlo;
            t0 = iTime(_Symbol, PERIOD_M30, a);
            t1 = iTime(_Symbol, PERIOD_M30, z);
            const datetime ot0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
            const datetime ot1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
            const double op0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
            const double op1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
            if(ot0 != t0 || ot1 != t1 || MathAbs(op0 - hi) > _Point || MathAbs(op1 - lo) > _Point)
              {
               ObjectSetInteger(0, name, OBJPROP_TIME, 0, t0);
               ObjectSetInteger(0, name, OBJPROP_TIME, 1, t1);
               ObjectSetDouble(0, name, OBJPROP_PRICE, 0, hi);
               ObjectSetDouble(0, name, OBJPROP_PRICE, 1, lo);
              }
           }
        }
      const double height = hi - lo;
      if(height <= _Point)
         continue;
      double h4span = 0.0;
      MqlRates h4[];
      if(CopyRates(_Symbol, PERIOD_H4, t1, 1, h4) == 1)
         h4span = h4[0].high - h4[0].low;
      double hvh = (h4span > 0.0) ? height / h4span : 0.0;
      double ov = 0.0;
      if(g_box.t_left > 0 && g_box.t_right > 0 && g_box.high > g_box.low)
        {
         datetime ta = (t0 > g_box.t_left) ? t0 : g_box.t_left;
         datetime tb = (t1 < g_box.t_right) ? t1 : g_box.t_right;
         datetime tmin = (t0 < g_box.t_left) ? t0 : g_box.t_left;
         datetime tmax = (t1 > g_box.t_right) ? t1 : g_box.t_right;
         const double dt = (tb > ta) ? (double)(tb - ta) : 0.0;
         const double du = (tmax > tmin) ? (double)(tmax - tmin) : 0.0;
         const double po = MathMax(0.0, MathMin(hi, g_box.high) - MathMax(lo, g_box.low));
         const double pu = MathMax(hi, g_box.high) - MathMin(lo, g_box.low);
         if(du > 0.0 && pu > 0.0)
            ov = (dt / du) * (po / pu);
        }
      string after = "WAIT";
      int after_dir = 0;
      int after_bars = 0;
      double after_size = 0.0;
      const int max_after = MathMax(2, InpBoxTimeout);
      if(shR > 1)
        {
         int seen = 0;
         for(int shk = shR - 1; shk >= 1 && seen < max_after; shk--)
           {
            const datetime bt = iTime(_Symbol, PERIOD_M30, shk);
            if(bt <= t1)
               continue;
            seen++;
            const double c = iClose(_Symbol, PERIOD_M30, shk);
            const bool hit_up = (c >= hi);
            const bool hit_dn = (c <= lo);
            if(hit_up && hit_dn)
              {
               after = "FAIL";
               after_bars = seen;
               break;
              }
            if(hit_up)
              {
               after = "UP";
               after_dir = 1;
               after_bars = seen;
               after_size = c - hi;
               break;
              }
            if(hit_dn)
              {
               after = "DN";
               after_dir = -1;
               after_bars = seen;
               after_size = lo - c;
               break;
              }
           }
        }
      const double avs = (height > 0.0) ? after_size / height : 0.0;
      FileWrite(fh, name,
                TimeToString(t0, TIME_DATE | TIME_MINUTES),
                TimeToString(t1, TIME_DATE | TIME_MINUTES),
                DoubleToString(hi, _Digits),
                DoubleToString(lo, _Digits),
                nb,
                DoubleToString(height, _Digits),
                DoubleToString(hvh, 3),
                DoubleToString(ov, 3),
                after,
                after_bars,
                DoubleToString(after_size, _Digits),
                DoubleToString(avs, 3));
      string mark = "saved " + after;
      color mclr = clrSilver;
      if(after_dir > 0)
         mclr = CLR_ARR_BUY;
      else if(after_dir < 0)
         mclr = CLR_ARR_SELL;
      ObjectSetString(0, name, OBJPROP_TOOLTIP,
                      "B100 " + mark + "  " + IntegerToString(nb) + " M30 in box  +" +
                      IntegerToString(after_bars) + " to break");
      const string tag = "B100H_ok_" + IntegerToString(kept);
      if(ObjectFind(0, tag) < 0)
         ObjectCreate(0, tag, OBJ_TEXT, 0, t0, hi);
      ObjectSetInteger(0, tag, OBJPROP_TIME, 0, t0);
      ObjectSetDouble(0, tag, OBJPROP_PRICE, 0, hi);
      ObjectSetString(0, tag, OBJPROP_TEXT, mark);
      ObjectSetString(0, tag, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, tag, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tag, OBJPROP_COLOR, mclr);
      ObjectSetInteger(0, tag, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, tag, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tag, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, tag, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M30);
      if(after_dir > 0)
         n_up++;
      else if(after_dir < 0)
         n_dn++;
      kept++;
     }
   FileClose(fh);
   if(kept != g_human_n)
     {
      g_human_n = kept;
      Print("B100 human boxes n=", kept, "  UP=", n_up, "  DN=", n_dn,
            "  file=BREAK100_human_box_", sym, ".csv");
     }
   else
      g_human_n = kept;
   s_busy = false;
   B100PaintHud();
  }

void B100HudLabel(const string name, const int x, const int y, const int fs,
                  const string font, const color clr, const string text)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   // An OBJ_LABEL whose OBJPROP_TEXT is "" does NOT render as nothing — the
   // terminal falls back to its default caption, the literal word "Label". Every
   // "this row has no content" branch below used to write "", so each one painted
   // a stray "Label" instead of disappearing: one in mint where HUMAN would go,
   // and one over the box row, because the empty rails label shares that row's y.
   // That is the overlap, and it is also why deleting an object *named* "Label"
   // never removed it. Hide the object instead, and only then set text.
   if(text == "")
     {
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
     }
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

// The on-chart dashboard. Grew from a bare SIGNAL+SL/TP1 line into a mirror of
// the Telegram WATCH alert (mode, auto-trade state, both rails, box-vs-floor,
// the learned policy's n and measured R) so the chart never needs Telegram open
// to show what will, or would, get traded. Height varies with content, so it
// reports its own bottom edge in g_dash_bottom_y for the buttons to anchor to.
// Fixed pixel strides, deliberately NOT measured via B100TextPx()/TextGetSize().
// TextGetSize() returns device-pixel dimensions, and on a scaled-DPI monitor
// that can come back far larger than expected — one such reading turned a
// dashboard that should span ~180px into one spanning 400+px, which in turn
// pushed g_dash_bottom_y (and the LIVE/ENTER buttons anchored to it) off the
// visible chart entirely. Fixed strides make the layout immune to that: it
// looks identical on every monitor because it never asks the renderer how
// big anything came out.
#define B100_ROW_BIG 22   // the headline signal row (16pt)
#define B100_ROW_SM  15   // every 9pt detail row

void B100PaintHud()
  {
   const int x = 14;
   const int y = 16;
   const int pad = 8;
   const int x_text = x + 16;
   const int box_w = 250;   // fixed; fits the longest line ("BUY  99999.99  SL 99999.99  r$999.99")
   const string font = "Georgia";
   const bool armed = (InpStrategy == B100_STRAT_BOX_M30 && g_box.ready && g_box.state == B100_BOX_ARMED);

   color clr = C'168,164,154';
   if(g_signal == "BUY") clr = CLR_BUY;
   else if(g_signal == "SELL") clr = CLR_SELL;
   else if(g_signal == "EXIT") clr = CLR_RES;
   else if(g_signal == "WATCH" || g_signal == "HOLD") clr = C'184,179,168';
   else if(g_signal == "STAND_DOWN") clr = CLR_SELL;

   int cy = y + pad;
   B100HudLabel(LBL_SIG, x_text, cy, 16, font, clr, g_signal);
   cy += B100_ROW_BIG + 4;

   // Mode / auto-trade — the number that answers "will this actually fire".
   const bool can_send = B100BrokerOrderIntentPermitted(g_mode);
   // "orders", not "auto": the question this row answers is whether anything
   // will actually reach the broker, and "auto OFF" was read as "manual trading
   // still works". It does not — OBSERVE sends nothing either way.
   const string mode_line = "mode " + B100ModeName(g_mode.mode) +
                            "   orders " + (can_send ? "ON" : "OFF");
   const color mode_clr = can_send ? C'110,180,130' : C'150,152,160';
   B100HudLabel(LBL_MODE, x_text, cy, 9, font, mode_clr, mode_line);
   cy += B100_ROW_SM + 2;

   // Both rails, same numbers as the Telegram WATCH alert.
   const double lots_per_leg = MathMax(InpLotsPerLeg, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   string buy1 = "", buy2 = "", sell1 = "", sell2 = "";
   if(g_oco_buy_px > 0.0)
     {
      buy1 = "BUY  " + B100Px(g_oco_buy_px) + "  SL " + B100Px(g_oco_sl_buy) +
             "  r$" + DoubleToString(B100MoneyRisk(MathAbs(g_oco_buy_px - g_oco_sl_buy), lots_per_leg), 2);
      buy2 = "     TP1 " + B100Px(g_oco_tp_buy) +
             ((g_oco_tp3_buy > 0.0 && g_oco_tp3_buy != g_oco_tp_buy) ? "  TP3 " + B100Px(g_oco_tp3_buy) : "");
     }
   if(g_oco_sell_px > 0.0)
     {
      sell1 = "SELL " + B100Px(g_oco_sell_px) + "  SL " + B100Px(g_oco_sl_sell) +
              "  r$" + DoubleToString(B100MoneyRisk(MathAbs(g_oco_sell_px - g_oco_sl_sell), lots_per_leg), 2);
      sell2 = "     TP1 " + B100Px(g_oco_tp_sell) +
              ((g_oco_tp3_sell > 0.0 && g_oco_tp3_sell != g_oco_tp_sell) ? "  TP3 " + B100Px(g_oco_tp3_sell) : "");
     }
   // Fallback for a filled/manual position where the OCO globals are cleared,
   // or a box that has armed but not yet reached level computation.
   string sub = "";
   if(buy1 == "" && sell1 == "")
     {
      if(g_levels.valid)
         sub = "SL " + B100Px(g_levels.sl) + "   TP1 " + B100Px(g_levels.tp1);
      else if(armed)
         sub = "BUY " + B100Px(g_box.buy_stop) + "  SELL " + B100Px(g_box.sell_stop);
     }

   if(buy1 != "")
     {
      B100HudLabel(LBL_BUY1, x_text, cy, 9, font, CLR_BUY, buy1);
      cy += B100_ROW_SM;
      B100HudLabel(LBL_BUY2, x_text, cy, 9, font, C'140,136,128', buy2);
      cy += B100_ROW_SM + 2;
     }
   else
     {
      B100HudLabel(LBL_BUY1, x_text, cy, 9, font, C'140,136,128', "");
      B100HudLabel(LBL_BUY2, x_text, cy, 9, font, C'140,136,128', "");
     }
   if(sell1 != "")
     {
      B100HudLabel(LBL_SELL1, x_text, cy, 9, font, CLR_SELL, sell1);
      cy += B100_ROW_SM;
      B100HudLabel(LBL_SELL2, x_text, cy, 9, font, C'140,136,128', sell2);
      cy += B100_ROW_SM + 2;
     }
   else
     {
      B100HudLabel(LBL_SELL1, x_text, cy, 9, font, C'140,136,128', "");
      B100HudLabel(LBL_SELL2, x_text, cy, 9, font, C'140,136,128', "");
     }
   if(sub != "")
     {
      B100HudLabel(LBL_LV, x_text, cy, 9, font, C'140,136,128', sub);
      cy += B100_ROW_SM + 3;
     }
   else
      B100HudLabel(LBL_LV, x_text, cy, 9, font, C'140,136,128', "");

   // Box height vs the execution size floor — same test B100ArmBoxOco runs.
   string boxinfo = "";
   color boxinfo_clr = C'140,136,128';
   if(g_box.height > 0.0)
     {
      const double spread_now = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                                        SymbolInfoDouble(_Symbol, SYMBOL_BID), _Point);
      const double h_spreads = (spread_now > 0.0) ? g_box.height / spread_now : 0.0;
      // Carry the floor, not just the verdict. "LOW" alone did not say low
      // against what, so the row could not be acted on without opening Inputs.
      boxinfo = "box " + DoubleToString(h_spreads, 1) + "x spread";
      if(InpMinBoxSpreads > 0.0)
        {
         const bool over_floor = (h_spreads >= InpMinBoxSpreads);
         boxinfo += " (need " + DoubleToString(InpMinBoxSpreads, 0) + "x)" +
                    (over_floor ? "  big enough" : "  TOO SMALL");
         boxinfo_clr = over_floor ? C'110,180,130' : C'196,164,92';
        }
     }
   if(boxinfo != "")
     {
      B100HudLabel(LBL_BOXINFO, x_text, cy, 9, font, boxinfo_clr, boxinfo);
      cy += B100_ROW_SM + 2;
     }
   else
      B100HudLabel(LBL_BOXINFO, x_text, cy, 9, font, C'140,136,128', "");

   // The learned policy. Sample size travels with the estimate on purpose — a
   // probability from 14 closed trades and one from 400 must not read the same.
   // "n=0 (DEFAULT)" read as a model that had scored zero. It means the opposite:
   // nothing has been learned yet, so the shipped defaults are in force.
   const string modelline = (g_policy.n <= 0)
                            ? "model  not trained yet, using defaults"
                            : ("model  " + IntegerToString(g_policy.n) + " trades (" +
                               g_policy.source + ")" +
                               (g_policy.mean_r != 0.0
                                ? "  R=" + DoubleToString(g_policy.mean_r, 3) : ""));
   B100HudLabel(LBL_MODEL, x_text, cy, 9, font, C'140,136,128', modelline);
   cy += B100_ROW_SM + 2;

   const bool has_hum = (g_human_n > 0);
   const string hum = has_hum ? ("HUMAN " + IntegerToString(g_human_n) + " saved") : "";
   if(has_hum)
     {
      B100HudLabel(LBL_HUM, x_text, cy, 9, font, CLR_ARR_BUY, hum);
      cy += B100_ROW_SM + 3;
     }
   else
      B100HudLabel(LBL_HUM, x_text, cy, 9, font, CLR_ARR_BUY, "");

   const int h = cy - y + pad;
   if(ObjectFind(0, HUD_BG) < 0)
      ObjectCreate(0, HUD_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, HUD_BG, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, HUD_BG, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, HUD_BG, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, HUD_BG, OBJPROP_XSIZE, box_w);
   ObjectSetInteger(0, HUD_BG, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, HUD_BG, OBJPROP_BGCOLOR, CLR_HUD);
   ObjectSetInteger(0, HUD_BG, OBJPROP_COLOR, C'42,46,56');
   ObjectSetInteger(0, HUD_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, HUD_BG, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, HUD_BG, OBJPROP_BACK, false);
   ObjectSetInteger(0, HUD_BG, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, HUD_BG, OBJPROP_HIDDEN, true);

   // Defensive clamp: even if some future line is added and this is forgotten
   // about, the buttons can never be pushed further than this off the top of
   // a normal-sized chart window.
   g_dash_bottom_y = MathMin(y + h + 10, 260);
  }

void B100PaintPanel()
  {
   Comment("");
   B100PaintHud();
  }

void B100PaintSignalLabel()
  {
   if(ObjectFind(0, LBL_SIG) < 0)
     {
      ObjectCreate(0, LBL_SIG, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, LBL_SIG, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, LBL_SIG, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, LBL_SIG, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, LBL_SIG, OBJPROP_YDISTANCE, 18);
      ObjectSetInteger(0, LBL_SIG, OBJPROP_FONTSIZE, 16);
      ObjectSetString(0, LBL_SIG, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, LBL_SIG, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, LBL_SIG, OBJPROP_HIDDEN, true);
     }
   if(ObjectFind(0, LBL_LV) < 0)
     {
      ObjectCreate(0, LBL_LV, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, LBL_LV, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, LBL_LV, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, LBL_LV, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, LBL_LV, OBJPROP_YDISTANCE, 42);
      ObjectSetInteger(0, LBL_LV, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, LBL_LV, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, LBL_LV, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, LBL_LV, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, LBL_LV, OBJPROP_COLOR, C'139,144,160');
     }
   color clr = C'139,144,160';
   if(g_signal == "BUY")
      clr = C'111,154,125';
   else if(g_signal == "SELL")
      clr = C'181,106,92';
   else if(g_signal == "EXIT")
      clr = C'196,164,92';
   else if(g_signal == "HOLD" || g_signal == "WATCH")
      clr = clrSilver;
   else if(g_signal == "STAND_DOWN")
      clr = C'181,106,92';
   ObjectSetInteger(0, LBL_SIG, OBJPROP_COLOR, clr);
   ObjectSetString(0, LBL_SIG, OBJPROP_TEXT, "SIGNAL  " + g_signal);
   ObjectSetString(0, LBL_LV, OBJPROP_TEXT, g_levels.valid ? B100LevelsText() : "");
  }

void B100LogNewBar(const string labeled)
  {
   const datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == g_last_bar)
     {
      if(labeled != "")
         Print("EVENT ", labeled, " SIGNAL=", g_signal, " ", B100LevelsText());
      return;
     }
   g_last_bar = t;
   PrintFormat("BAR %s SIGNAL=%s issued=%s hypo=%s SafeEV=%.3f %s",
               TimeToString(t, TIME_DATE|TIME_MINUTES),
               g_signal,
               B100ActionName(g_decision.action),
               B100ActionName(g_decision.hypothetical),
               g_decision.safe_ev,
               B100LevelsText());
  }
