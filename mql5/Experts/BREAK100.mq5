#property copyright "BREAK100"
#property version   "1.42"
#property description "Observe/Shadow on demo or real. Data only. No orders."

#include <Break100/Channel.mqh>
#include <Break100/Mode.mqh>
#include <Break100/SafeEV.mqh>
#include <Break100/Risk.mqh>
#include <Break100/Shadow.mqh>
#include <Break100/Learner.mqh>

input ENUM_B100_MODE InpMode           = B100_OBSERVE; // Operating mode (Demo/Live are rejected)

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

   if(InpAttachIndicator)
     {
      g_ind_handle = iCustom(_Symbol, PERIOD_CURRENT, "BREAK100_Channel",
                             InpMadWindow, InpKalmanQ, InpKalmanRFloor, InpMadK);
      if(g_ind_handle != INVALID_HANDLE)
         ChartIndicatorAdd(0, 0, g_ind_handle);
     }

   B100CreateLines();
   B100LevelLine(LV_ENTRY, mid, clrSilver, STYLE_DOT, "ENTRY");
   B100LevelLine(LV_SL,    mid, C'181,106,92', STYLE_SOLID, "SL");
   B100LevelLine(LV_TP1,   mid, C'111,154,125', STYLE_DASH, "TP1");
   B100LevelLine(LV_TP2,   mid, C'90,140,110', STYLE_DASH, "TP2");
   B100LevelLine(LV_TP3,   mid, C'70,120,95', STYLE_DASH, "TP3");
   g_ready = true;

   Print("BREAK100 init  mode=", B100ModeName(g_mode.mode),
         "  health=", (g_mode.health == B100_HEALTHY ? "HEALTHY" : "FAULT"),
         "  orders=OFF  account=", (B100IsDemoAccount() ? "DEMO" : (B100IsRealAccount() ? "REAL" : "UNKNOWN")),
         "  learner_n=", g_learner.n, "  policy=", g_policy.source);
   if(g_init_note != "")
      Print(g_init_note);
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
   ObjectsDeleteAll(0, "B100_ev_");
   B100LearnerSave(g_learner);
   Comment("");
  }

void OnTick()
  {
   if(!g_ready || g_mode.health != B100_HEALTHY)
     {
      g_signal = "STAND_DOWN";
      g_signal_note = (g_mode.block_reason == "" ? "FAULT" : g_mode.block_reason);
      B100PaintPanel();
      return;
     }

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0 || ask < bid)
     {
      B100FailClosed(g_mode, "TICK_INVALID");
      g_signal = "STAND_DOWN";
      g_signal_note = "TICK_INVALID";
      B100PaintPanel();
      return;
     }

   const string labeled = B100Ingest(g_pipe, bid, ask);
   if(labeled != "")
     {
      g_last_event = labeled;
      B100LearnerPolicy(g_learner, g_pipe.last_label_side, g_policy);
     }

   B100Costs costs;
   costs.spread     = InpCostSpread;
   costs.commission = InpCostCommission;
   costs.slippage   = InpCostSlippage;

   B100Decide(g_decision,
              g_pipe.n_break_up, g_pipe.n_break_dn, g_pipe.n_bounce, g_pipe.n_censored,
              costs, InpUncertaintyK, InpMinSamples,
              (g_mode.health == B100_HEALTHY),
              B100BrokerOrderIntentPermitted(g_mode));

   B100RiskSnap snap;
   snap.loss_24h         = 0.0;
   snap.loss_week        = 0.0;
   snap.drawdown         = 0.0;
   snap.open_for_symbol  = g_shadow.open ? 1 : 0;
   g_risk_code = B100RiskGate(snap);

   const bool shadow_was_open = g_shadow.open;
   if(g_mode.mode == B100_SHADOW && InpShadowLedger)
      B100ShadowStep(bid, ask, labeled);
   const bool shadow_closed = (shadow_was_open && !g_shadow.open);

   B100ComputeSignal(labeled, shadow_was_open, shadow_closed, bid, ask);
   if(labeled != "")
     {
      B100LearnerObserve(g_learner, g_pipe.last_label_side, labeled,
                         g_pipe.last_mfe, g_pipe.last_mae, g_pipe.last_hw);
      if((g_learner.n % 8) == 0)
         B100LearnerSave(g_learner);
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

   if(!g_pipe.warmed)
     {
      next = "WAIT";
      note = "warmup — wait for ~12 ticks, width settles ~160";
      g_levels.valid = false;
     }
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
      B100FillLevels(1, ask, ask, bid);
      if(g_decision.hypothetical == B100_ENTER_LONG && g_decision.safe_ev > 0.0 && g_risk_code == "RISK_GATE_PASSED")
        {
         next = "BUY";
         note = "BREAKOUT_UP + SafeEV>0 — Observe only";
        }
      else
        {
         next = "STAND_DOWN";
         note = "BREAKOUT_UP but " + g_decision.reason;
        }
      g_signal_seq = g_pipe.seq;
      B100MarkEvent(labeled, mid);
     }
   else if(labeled == "BREAKOUT_DOWN")
     {
      B100FillLevels(-1, bid, ask, bid);
      if(g_decision.hypothetical == B100_ENTER_SHORT && g_decision.safe_ev > 0.0 && g_risk_code == "RISK_GATE_PASSED")
        {
         next = "SELL";
         note = "BREAKOUT_DOWN + SafeEV>0 — Observe only";
        }
      else
        {
         next = "STAND_DOWN";
         note = "BREAKOUT_DOWN but " + g_decision.reason;
        }
      g_signal_seq = g_pipe.seq;
      B100MarkEvent(labeled, mid);
     }
   else if(labeled == "BOUNCE" || labeled == "CENSORED_OR_AMBIGUOUS")
     {
      next = (shadow_was_open || g_last_alert == "HOLD") ? "EXIT" : "WAIT";
      note = labeled + " — no entry";
      g_signal_seq = g_pipe.seq;
      B100MarkEvent(labeled, mid);
     }
   else if(g_pipe.pending.active)
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
   B100HLine(LINE_MID, clrSilver, STYLE_DOT);
   B100HLine(LINE_UP,  C'139,144,160', STYLE_SOLID);
   B100HLine(LINE_DN,  C'139,144,160', STYLE_SOLID);
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

void B100UpdateLines()
  {
   if(!InpDrawChannel)
      return;
   ObjectSetDouble(0, LINE_MID, OBJPROP_PRICE, g_pipe.kalman_x);
   ObjectSetDouble(0, LINE_UP,  OBJPROP_PRICE, g_pipe.kalman_x + g_pipe.half_width);
   ObjectSetDouble(0, LINE_DN,  OBJPROP_PRICE, g_pipe.kalman_x - g_pipe.half_width);
  }

void B100PaintPanel()
  {
   const string mode = B100ModeName(g_mode.mode);
   const string health = (g_mode.health == B100_HEALTHY) ? "HEALTHY" : "FAULT";
   const double mid = 0.5 * (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   string text =
      "SIGNAL  " + g_signal + "\n" +
      g_signal_note + "\n" +
      B100LevelsText() + "\n" +
      "learn  n=" + IntegerToString(g_policy.n) +
      "  " + g_policy.source +
      "  arm=" + g_policy.arm_id +
      "  meanR=" + DoubleToString(g_policy.mean_r, 3) +
      "  slR=" + DoubleToString(g_policy.sl_r, 2) +
      "  tpR=" + DoubleToString(g_policy.tp1_r, 2) +
      "/" + DoubleToString(g_policy.tp2_r, 2) +
      "/" + DoubleToString(g_policy.tp3_r, 2) + "\n" +
      "do not send an order — issued NO_TRADE\n" +
      "--------------------------------\n" +
      "BREAK100  " + mode + "  " + health + "  orders OFF\n" +
      _Symbol + "  " + EnumToString(_Period) + "\n" +
      "mid " + DoubleToString(mid, _Digits) +
      "  centre " + DoubleToString(g_pipe.kalman_x, _Digits) +
      "  hw " + DoubleToString(g_pipe.half_width, _Digits) + "\n" +
      "touch " + IntegerToString(g_pipe.touch_count) +
      "  up " + IntegerToString(g_pipe.n_break_up) +
      "  dn " + IntegerToString(g_pipe.n_break_dn) +
      "  bounce " + IntegerToString(g_pipe.n_bounce) +
      "  cens " + IntegerToString(g_pipe.n_censored) + "\n" +
      "issued " + B100ActionName(g_decision.action) + "  " + g_decision.reason + "\n" +
      "hypo   " + B100ActionName(g_decision.hypothetical) + "  SafeEV " + DoubleToString(g_decision.safe_ev, 3) + "\n" +
      "risk   " + g_risk_code + "\n" +
      "shadow " + (g_shadow.open ? "OPEN" : "flat") +
      "  pnl " + DoubleToString(g_shadow.realized, 2) +
      "  n " + IntegerToString(g_shadow.trades) + "\n" +
      (g_last_event == "" ? "event  —" : ("event  " + g_last_event)) +
      (g_mode.block_reason == "" ? "" : ("\nblock  " + g_mode.block_reason));

   Comment(text);
   B100PaintSignalLabel();
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
