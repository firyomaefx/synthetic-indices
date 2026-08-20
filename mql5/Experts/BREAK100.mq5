#property copyright "BREAK100"
#property version   "1.70"
#property description "Observe/Shadow/DEMO_AUTO(demo only). Live locked. No profit claim."

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

input ENUM_B100_MODE InpMode           = B100_OBSERVE; // OBSERVE/SHADOW/DEMO(demo account). LIVE rejected.
input ENUM_B100_STRAT InpStrategy      = B100_STRAT_BOX_M30; // CHANNEL tick band, or M30 box breakout

input ENUM_TIMEFRAMES InpBoxTF         = PERIOD_M30;   // Box timeframe
input int            InpBoxMinBars     = 3;            // Min bars in a pause cluster
input int            InpBoxMaxBars     = 8;            // Max bars in a pause cluster
input int            InpBoxAtrPeriod   = 14;           // ATR for "tight" test
input double         InpBoxAtrMax      = 0.95;         // Cluster range must be <= this × ATR
input int            InpBoxTimeout     = 10;           // Armed bars without fill → cancel
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

input bool           InpUseLearner     = true;         // Dynamic SL/TP from closed labels
input bool           InpShadowLedger   = true;         // Virtual fills in SHADOW
input bool           InpDrawChannel    = true;         // Draw channel lines
input bool           InpAttachIndicator= true;         // Attach visual indicator
input bool           InpDrawArrows     = true;         // Arrows on buy/sell/exit
input bool           InpDrawLevels     = true;         // Draw entry/SL/TP lines
input bool           InpAlerts         = true;         // Popup on BUY/SELL/EXIT
input bool           InpCapture        = true;         // Ticks + M1-H4 + ARM setup before breakout

#define IND_SHORT  "BREAK100 Channel"
#define LINE_MID   "B100_centre"
#define LINE_UP    "B100_upper"
#define LINE_DN    "B100_lower"
#define LBL_SIG    "B100_signal"
#define LBL_LV     "B100_levels"
#define LV_ENTRY   "B100_lv_entry"
#define LV_SL      "B100_lv_sl"
#define LV_TP1     "B100_lv_tp1"
#define LV_TP2     "B100_lv_tp2"
#define LV_TP3     "B100_lv_tp3"
#define BOX_RECT   "B100_box"
#define BOX_RES    "B100_box_res"
#define BOX_SUP    "B100_box_sup"
#define BOX_MID    "B100_box_mid"
#define BOX_BUY    "B100_box_buystop"
#define BOX_SELL   "B100_box_sellstop"
#define BOX_RES_LBL "B100_box_res_lbl"
#define BOX_SUP_LBL "B100_box_sup_lbl"
#define HUD_BG     "B100_hud_bg"

#define CLR_INK      C'11,13,18'
#define CLR_HUD      C'16,18,24'
#define CLR_BOX_FILL C'22,28,38'
#define CLR_RES      C'198,162,98'
#define CLR_SUP      C'86,138,128'
#define CLR_EQ       C'120,118,108'
#define CLR_BUY      C'212,175,106'
#define CLR_SELL     C'186,96,96'

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

B100Pipe        g_pipe;
B100Mode        g_mode;
B100ShadowBook  g_shadow;
B100Decision    g_decision;
B100Levels      g_levels;
B100Learner     g_learner;
B100LearnPolicy g_policy;
B100Box         g_box;
B100Capture     g_capture;
int             g_ind_handle = INVALID_HANDLE;
bool            g_ready      = false;
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
bool            g_skin_on    = false;
color           g_old_bg, g_old_fg, g_old_grid, g_old_up, g_old_dn, g_old_bull, g_old_bear, g_old_ask, g_old_bid, g_old_vol;
bool            g_old_show_grid, g_old_show_vol, g_old_show_ohlc, g_old_show_ask;

void B100PaintBox();
void B100PaintHud();
void B100ApplyChartSkin();
void B100RestoreChartSkin();
void B100MarkBoxSignal(const int dir, const double price);

int OnInit()
  {
   g_init_note = B100ApplyRequestedMode(g_mode, InpMode);
   if(B100IsRealAccount() && (InpMode == B100_DEMO || InpMode == B100_LIVE))
     {
      g_mode.mode         = B100_OBSERVE;
      g_mode.health       = B100_HEALTHY;
      g_mode.block_reason = "REAL_ACCOUNT_DATA_ONLY";
      g_init_note = "REAL_ACCOUNT_DATA_ONLY: demo/live inputs ignored — Observe/Shadow for ticks, no orders";
     }

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double mid = (bid > 0.0 && ask > 0.0) ? 0.5 * (bid + ask) : SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   B100PipeInit(g_pipe, mid, InpMadWindow, InpKalmanQ, InpKalmanRFloor, InpMadK,
                InpPersistTicks, InpLabelHorizon);
   B100ShadowInit(g_shadow);
   ZeroMemory(g_levels);
   B100LearnerInit(g_learner);
   B100BoxInit(g_box);
   B100BoxScanHistory(g_box, InpBoxTF, InpBoxMinBars, InpBoxMaxBars, InpBoxAtrPeriod, InpBoxAtrMax);
   B100CaptureInit(g_capture, InpCapture);
   B100LearnerLoad(g_learner);
   if(B100PolicyLoad(g_policy))
     {
      g_learner.last_arm = g_policy.arm;
      Print("BREAK100 loaded offline policy  source=", g_policy.source,
            " n=", g_policy.n, " arm=", g_policy.arm_id,
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
   B100LevelLine(LV_ENTRY, mid, clrSilver, STYLE_DOT, "ENTRY");
   B100LevelLine(LV_SL,    mid, C'181,106,92', STYLE_SOLID, "SL");
   B100LevelLine(LV_TP1,   mid, C'111,154,125', STYLE_DASH, "TP1");
   B100LevelLine(LV_TP2,   mid, C'90,140,110', STYLE_DASH, "TP2");
   B100LevelLine(LV_TP3,   mid, C'70,120,95', STYLE_DASH, "TP3");
   g_ready = true;

   Print("BREAK100 init  mode=", B100ModeName(g_mode.mode),
         "  health=", (g_mode.health == B100_HEALTHY ? "HEALTHY" : "FAULT"),
         "  orders=OFF  account=", (B100IsDemoAccount() ? "DEMO" : (B100IsRealAccount() ? "REAL" : "UNKNOWN")),
         "  strat=", (InpStrategy == B100_STRAT_BOX_M30 ? "BOX_M30" : "CHANNEL"),
         "  learner_n=", g_learner.n, "  policy=", g_policy.source);
   if(g_init_note != "")
      Print(g_init_note);
   B100ApplyChartSkin();
   if(InpStrategy == B100_STRAT_BOX_M30)
      B100PaintBox();
   B100PaintPanel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
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
   ObjectDelete(0, LV_ENTRY);
   ObjectDelete(0, LV_SL);
   ObjectDelete(0, LV_TP1);
   ObjectDelete(0, LV_TP2);
   ObjectDelete(0, LV_TP3);
   ObjectDelete(0, BOX_RECT);
   ObjectDelete(0, BOX_RES);
   ObjectDelete(0, BOX_SUP);
   ObjectDelete(0, BOX_MID);
   ObjectDelete(0, BOX_BUY);
   ObjectDelete(0, BOX_SELL);
   ObjectDelete(0, BOX_RES_LBL);
   ObjectDelete(0, BOX_SUP_LBL);
   ObjectDelete(0, HUD_BG);
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
   if(g_ready && bid > 0.0 && ask >= bid)
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

   if(InpStrategy == B100_STRAT_BOX_M30)
     {
      labeled = B100BoxOnTick(g_box, InpBoxTF, InpBoxMinBars, InpBoxMaxBars,
                              InpBoxAtrPeriod, InpBoxAtrMax, InpBoxTimeout, bid, ask);
      if(g_box.just_armed)
        {
         B100CaptureSetup(g_capture, g_box, bid, ask);
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

   const bool shadow_was_open = g_shadow.open;
   if(g_mode.mode == B100_SHADOW && InpShadowLedger)
      B100ShadowStep(bid, ask, labeled);
   const bool shadow_closed = (shadow_was_open && !g_shadow.open);

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
         B100LearnerObserve(g_learner, learn_side, labeled, learn_mfe, learn_mae, learn_hw);
         B100LearnerSave(g_learner);
         if(InpStrategy == B100_STRAT_BOX_M30)
            B100CaptureOutcome(g_capture, g_box, labeled, bid, ask);
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
         if(B100BrokerOrderIntentPermitted(g_mode) && g_box.armed_bar != g_last_exec_bar && lots > 0.0)
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
   B100UpdateLines();
   B100PaintLevels();
   B100PaintPanel();
   B100LogNewBar(labeled);
  }

void B100FillLevels(const int dir, const double entry, const double ask, const double bid)
  {
   const double spread = MathMax(ask - bid, _Point);
   double sl_hw = InpStopAtrMult;
   double tp1_hw = InpTp1R * sl_hw;
   double tp2_hw = InpTp2R * sl_hw;
   double tp3_hw = InpTp3R * sl_hw;
   if(InpUseLearner)
     {
      sl_hw  = g_policy.sl_r;
      tp1_hw = g_policy.tp1_r;
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
   const double d1 = MathMax(tp1_hw * g_pipe.half_width, 0.5 * stop_dist);
   const double d2 = MathMax(tp2_hw * g_pipe.half_width, d1 + 0.2 * g_pipe.half_width);
   const double d3 = MathMax(tp3_hw * g_pipe.half_width, d2 + 0.2 * g_pipe.half_width);
   g_levels.tp1   = entry + dir * d1;
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
   g_levels.valid = true;
   g_levels.dir   = dir;
   g_levels.entry = stop_px;
   g_levels.r     = MathAbs(stop_px - other);
   g_levels.sl    = other;
   if((dir > 0 && g_levels.sl >= g_levels.entry) || (dir < 0 && g_levels.sl <= g_levels.entry))
      g_levels.sl = g_levels.entry - dir * MathMax(2.0 * spread, 0.5 * H);
   g_levels.tp1 = g_levels.entry + dir * H * MathMax(tp1m, 0.5);
   g_levels.tp2 = g_levels.entry + dir * H * MathMax(tp2m, tp1m + 0.2);
   g_levels.tp3 = g_levels.entry + dir * H * MathMax(tp3m, tp2m + 0.2);
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
         B100ShadowClose(g_shadow, px);
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
         B100ShadowClose(g_shadow, 0.5 * (bid + ask));
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

   if(box_mode && !g_box.ready)
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
      if(box_mode && next == "BUY")
         B100MarkBoxSignal(1, mid);
      else if(!box_mode)
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
      if(box_mode && next == "SELL")
         B100MarkBoxSignal(-1, mid);
      else if(!box_mode)
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
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
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

void B100LevelLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style, const string caption)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, g_levels.valid && InpDrawLevels ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, caption + " " + DoubleToString(price, _Digits));
  }

void B100PaintLevels()
  {
   if(InpDrawLevels && InpStrategy == B100_STRAT_BOX_M30 &&
      g_box.ready && g_box.state == B100_BOX_ARMED &&
      (g_signal == "WATCH" || g_signal == "WAIT"))
     {
      B100LevelLine(LV_ENTRY, 0.5 * (g_box.high + g_box.low), CLR_EQ, STYLE_DOT, "BOX MID");
      B100LevelLine(LV_SL,    g_box.sell_stop, CLR_SELL, STYLE_SOLID, "SELL STOP");
      B100LevelLine(LV_TP1,   g_box.buy_stop,  CLR_BUY,  STYLE_SOLID, "BUY STOP");
      ObjectSetInteger(0, LV_TP2, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, LV_TP3, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
     }
   const bool show = InpDrawLevels && g_levels.valid &&
                     (g_signal == "BUY" || g_signal == "SELL" || g_signal == "HOLD" ||
                      g_signal == "STAND_DOWN" || g_signal == "EXIT");
   if(!show)
     {
      ObjectSetInteger(0, LV_ENTRY, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, LV_SL,    OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, LV_TP1,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, LV_TP2,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, LV_TP3,   OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
     }
   B100LevelLine(LV_ENTRY, g_levels.entry, clrSilver,            STYLE_DOT,   "ENTRY");
   B100LevelLine(LV_SL,    g_levels.sl,    C'181,106,92',        STYLE_SOLID, "SL");
   B100LevelLine(LV_TP1,   g_levels.tp1,   C'111,154,125',       STYLE_DASH,  "TP1");
   B100LevelLine(LV_TP2,   g_levels.tp2,   C'90,140,110',        STYLE_DASH,  "TP2");
   B100LevelLine(LV_TP3,   g_levels.tp3,   C'70,120,95',         STYLE_DASH,  "TP3");
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
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
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
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
  }

void B100PaintBox()
  {
   static int last_hist = -1;
   if(g_box.hist_n != last_hist)
     {
      B100PaintHistBoxes();
      last_hist = g_box.hist_n;
     }
   if(InpStrategy != B100_STRAT_BOX_M30 || !g_box.ready)
     {
      ObjectSetInteger(0, BOX_RECT,    OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_RES,     OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_SUP,     OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_MID,     OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_BUY,     OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_SELL,    OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_RES_LBL, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_SUP_LBL, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
     }
   const datetime t1 = TimeCurrent() + PeriodSeconds(PERIOD_M30) * 6;
   const datetime t0 = (g_box.t_left > 0) ? g_box.t_left : iTime(_Symbol, PERIOD_M30, 8);
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
   ObjectSetInteger(0, BOX_RECT, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

   B100BoxRail(BOX_RES, t0, t1, g_box.high, CLR_RES, 2);
   B100BoxRail(BOX_SUP, t0, t1, g_box.low,  CLR_SUP, 2);
   B100BoxRail(BOX_MID, t0, t1, 0.5 * (g_box.high + g_box.low), CLR_EQ, 1);
   if(g_box.state == B100_BOX_ARMED)
     {
      B100BoxRail(BOX_BUY,  t0, t1, g_box.buy_stop,  CLR_BUY,  2);
      B100BoxRail(BOX_SELL, t0, t1, g_box.sell_stop, CLR_SELL, 2);
     }
   else
     {
      ObjectSetInteger(0, BOX_BUY,  OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      ObjectSetInteger(0, BOX_SELL, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
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

void B100MarkBoxSignal(const int dir, const double price)
  {
   if(!InpDrawArrows)
      return;
   // OCO fills on the live tick (bar 0). Bar 1 is the previous closed M30 — that looked lagged.
   datetime bar0 = iTime(_Symbol, PERIOD_M30, 0);
   if(bar0 <= 0)
      bar0 = TimeCurrent();
   const datetime t = TimeCurrent();
   const string name = "B100_box_ev_" + IntegerToString((int)bar0);
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, (dir > 0) ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, (dir > 0) ? CLR_BUY : CLR_SELL);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 4);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

void B100PaintHud()
  {
   const int x = 14;
   const int y = 16;
   const bool armed = (InpStrategy == B100_STRAT_BOX_M30 && g_box.ready && g_box.state == B100_BOX_ARMED);
   const int h = (g_levels.valid || armed) ? 78 : 56;
   if(ObjectFind(0, HUD_BG) < 0)
      ObjectCreate(0, HUD_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, HUD_BG, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, HUD_BG, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, HUD_BG, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, HUD_BG, OBJPROP_XSIZE, 168);
   ObjectSetInteger(0, HUD_BG, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, HUD_BG, OBJPROP_BGCOLOR, CLR_HUD);
   ObjectSetInteger(0, HUD_BG, OBJPROP_COLOR, C'42,46,56');
   ObjectSetInteger(0, HUD_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, HUD_BG, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, HUD_BG, OBJPROP_BACK, false);
   ObjectSetInteger(0, HUD_BG, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, HUD_BG, OBJPROP_HIDDEN, true);

   color clr = C'168,164,154';
   if(g_signal == "BUY") clr = CLR_BUY;
   else if(g_signal == "SELL") clr = CLR_SELL;
   else if(g_signal == "EXIT") clr = CLR_RES;
   else if(g_signal == "WATCH" || g_signal == "HOLD") clr = C'184,179,168';
   else if(g_signal == "STAND_DOWN") clr = CLR_SELL;

   if(ObjectFind(0, LBL_SIG) < 0)
      ObjectCreate(0, LBL_SIG, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_SIG, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, LBL_SIG, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, LBL_SIG, OBJPROP_XDISTANCE, x + 16);
   ObjectSetInteger(0, LBL_SIG, OBJPROP_YDISTANCE, y + 10);
   ObjectSetInteger(0, LBL_SIG, OBJPROP_FONTSIZE, 22);
   ObjectSetString(0, LBL_SIG, OBJPROP_FONT, "Georgia");
   ObjectSetInteger(0, LBL_SIG, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, LBL_SIG, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, LBL_SIG, OBJPROP_HIDDEN, true);
   ObjectSetString(0, LBL_SIG, OBJPROP_TEXT, g_signal);

   string sub = "";
   if(g_levels.valid)
      sub = "SL " + DoubleToString(g_levels.sl, _Digits) + "   TP1 " + DoubleToString(g_levels.tp1, _Digits);
   else if(armed)
      sub = "BUY " + DoubleToString(g_box.buy_stop, _Digits) + "  SELL " + DoubleToString(g_box.sell_stop, _Digits);
   if(ObjectFind(0, LBL_LV) < 0)
      ObjectCreate(0, LBL_LV, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_LV, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, LBL_LV, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, LBL_LV, OBJPROP_XDISTANCE, x + 16);
   ObjectSetInteger(0, LBL_LV, OBJPROP_YDISTANCE, y + 42);
   ObjectSetInteger(0, LBL_LV, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, LBL_LV, OBJPROP_FONT, "Georgia");
   ObjectSetInteger(0, LBL_LV, OBJPROP_COLOR, C'140,136,128');
   ObjectSetInteger(0, LBL_LV, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, LBL_LV, OBJPROP_HIDDEN, true);
   ObjectSetString(0, LBL_LV, OBJPROP_TEXT, sub);
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
