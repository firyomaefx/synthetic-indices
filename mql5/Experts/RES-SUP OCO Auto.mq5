#property copyright "Break100 Box Trading"
#property version   "1.00"
#property description "Automated counterpart to Scripts/RES-SUP OCO.mq5. Places a BUY STOP +"
#property description "SELL STOP OCO pair off the chart's RES/SUP rails the moment they change,"
#property description "with no manual launch. Cancels the sibling on fill. Runs unattended."
#property description "1.00  LIVE ACCOUNTS ENABLED (owner authorised, same as the manual script)."

// This is the manual RES-SUP OCO.mq5, restructured from a one-shot Script into an
// Expert Advisor so it can run unattended. The trade math (buy/sell stop, SL, TP)
// and every helper function below are ported verbatim from that script -- see it
// for the line-by-line rationale of each formula. The only genuinely new part is
// the state machine replacing OnStart()'s single pass + 500ms poll loop with
// OnTick(), because a Script has no OnTick and an EA has no other way to notice
// a new box without a person launching it.
//
// Detection of a new box does NOT read anything from the detection EA's internal
// state, a GlobalVariable, or a capture CSV -- it just polls the same two chart
// objects the manual script already reads (B100_box_res / B100_box_sup, drawn by
// "Break100 Box Trading.mq5"). This keeps the detection EA, Box.mqh and the manual
// script completely untouched by this file's existence.
//
// *** THIS TRADES REAL MONEY ON A LIVE ACCOUNT, AUTOMATICALLY, ON EVERY FUTURE BOX
// ARM, WITH NO FURTHER HUMAN REVIEW. *** Attaching this EA is the arming gesture --
// there is no separate button. InpAllowLiveTrading defaults to true, matching the
// manual script's already-owner-authorised default (DECISION_LOG D-007). Set it to
// false to make every future attempt a logged no-op.
//
// Read this before attaching to a live chart: the strategy this places orders for
// has NO MEASURED EDGE. research/BACKTEST_RESULTS.md, over 3.56M ticks and 41 days,
// puts the shipped baseline at -4.90% ROI and -0.164R expectancy, with the best of
// 20 configurations reaching t=+0.12 against the ~2.45 needed to clear the
// trial-count bar. Automating does not change the edge -- it changes the account
// from "bleeds only when a human clicks" to "bleeds on a fixed schedule regardless."
//
// MANUAL TEST (demo account first, always -- same procedure as the script, adapted
// for unattended operation):
//   1. Attach to a BREAK100 chart that already shows RES/SUP (either the main EA's
//      WATCH state, or two horizontal lines you name to match
//      InpResObjectName/InpSupObjectName).
//   2. Attach on a DEMO account first. Wait for (or manually set InpManualRes/
//      InpManualSup on a duplicate demo chart to force) a box. Confirm both a BUY
//      STOP and a SELL STOP appear in the Trade tab, each with nonzero SL/TP,
//      with NO manual action from you.
//   3. Let one side fill (or move price in Strategy Tester). Confirm the sibling
//      pending is gone within ~1s and the log shows which side filled.
//   4. Confirm it correctly arms again on the NEXT distinct box -- this is the one
//      behaviour the manual script never had to prove, because a human launched it
//      fresh every time.
//   5. Only then attach to the live chart, at InpLots you can afford to lose.

#include <Break100/Mode.mqh>       // B100IsDemoAccount / B100IsRealAccount
#include <Break100/DemoExec.mqh>   // B100FreezePrice (pure; tick-size normalisation)

// Distinct from the main EA's B100_MAGIC (100165, DemoExec.mqh:12) and the manual
// script's RESSUP_MAGIC (100265), so all three can never cross-react even if all
// three are ever attached to the same symbol at once.
#define RESSUP_AUTO_MAGIC 100365

input string InpResObjectName    = "B100_box_res";  // Chart object to read RES (resistance) from
input string InpSupObjectName    = "B100_box_sup";  // Chart object to read SUP (support) from
input double InpManualRes        = 0.0;             // Used only if the RES object isn't found (0 = none)
input double InpManualSup        = 0.0;             // Used only if the SUP object isn't found (0 = none)
input double InpOffsetPct        = 0.02;            // Stop offset beyond RES/SUP, as a fraction of height
input double InpSlBufR           = 0.15;            // SL beyond opposite rail, in box heights
input double InpTp1R             = 1.0;             // TP as a multiple of the stop distance (R)
input double InpLots             = 0.01;            // Lot size per leg -- change to suit your account
input int    InpTimeoutMinutes   = 240;             // Cancel both and exit if neither fills in time
input bool   InpAllowLiveTrading = true;            // REAL MONEY on a live account. Set false to disable.

enum ENUM_RESSUP_STATE
  {
   RESSUP_IDLE,          // watching for a new (res, sup) pair
   RESSUP_ARMED_PENDING  // both legs placed, waiting for a fill or timeout
  };

ENUM_RESSUP_STATE g_state = RESSUP_IDLE;

// Sentinel: no real BREAK100 price is <= 0, so this guarantees the first valid
// pair ever seen is treated as new.
double g_last_res = -1.0;
double g_last_sup = -1.0;

ulong  g_buy_tk = 0;
ulong  g_sell_tk = 0;
ulong  g_deadline = 0;
ulong  g_known[];   // positions under our magic that existed before this cycle's placement

// ---------------------------------------------------------------------------
// Below this line: ported verbatim from Scripts/RES-SUP OCO.mq5, retagged with
// RESSUP_AUTO_MAGIC instead of RESSUP_MAGIC. See that file for the rationale of
// each guard -- it is not repeated here.
// ---------------------------------------------------------------------------

bool ResSupAccountOk(void)
  {
   if(B100IsDemoAccount())
      return true;
   if(!B100IsRealAccount())
      return false;
   return InpAllowLiveTrading;
  }

bool CancelTicket(const ulong ticket, string &err)
  {
   err = "";
   if(ticket == 0)
      return true;
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;
   ResetLastError();
   if(!OrderSend(req, res))
     {
      err = "CANCEL_FAIL " + IntegerToString((int)res.retcode) +
            " last=" + IntegerToString(GetLastError());
      return false;
     }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
     {
      err = "CANCEL_RETCODE=" + IntegerToString((int)res.retcode);
      return false;
     }
   Print("RES-SUP OCO Auto: cancelled ticket=", ticket);
   return true;
  }

bool ReadLevel(const string obj_name, const double manual, double &out_price)
  {
   if(ObjectFind(0, obj_name) >= 0)
     {
      out_price = ObjectGetDouble(0, obj_name, OBJPROP_PRICE, 0);
      return out_price > 0.0;
     }
   if(manual > 0.0)
     {
      out_price = manual;
      return true;
     }
   return false;
  }

bool PlacePending(const ENUM_ORDER_TYPE typ, const double price, const double sl,
                  const double tp, ulong &ticket, string &err)
  {
   err = "";
   ticket = 0;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      err = "TRADE_DISABLED";
      return false;
     }
   if(InpLots <= 0.0 || price <= 0.0 || sl <= 0.0)
     {
      err = "SL_OR_LOTS_INVALID";
      return false;
     }
   const double px  = B100FreezePrice(price);
   const double slx = B100FreezePrice(sl);
   const double tpx = (tp > 0.0) ? B100FreezePrice(tp) : 0.0;
   if(typ == ORDER_TYPE_BUY_STOP && slx >= px)
     {
      err = "SL_NOT_BELOW_BUY_STOP";
      return false;
     }
   if(typ == ORDER_TYPE_SELL_STOP && slx <= px)
     {
      err = "SL_NOT_ABOVE_SELL_STOP";
      return false;
     }

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = _Symbol;
   req.volume       = InpLots;
   req.type         = typ;
   req.price        = px;
   req.sl           = slx;
   req.tp           = tpx;
   req.magic        = RESSUP_AUTO_MAGIC;
   req.comment      = "RESSUP-OCO-AUTO";
   req.type_time    = ORDER_TIME_GTC;
   req.type_filling = ORDER_FILLING_RETURN;
   ResetLastError();
   if(!OrderSend(req, res))
     {
      err = "PENDING_FAIL " + IntegerToString((int)res.retcode) +
            " last=" + IntegerToString(GetLastError());
      return false;
     }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
     {
      err = "PENDING_RETCODE=" + IntegerToString((int)res.retcode);
      return false;
     }
   ticket = res.order;
   return true;
  }

bool TicketIsPending(const ulong ticket)
  {
   if(ticket == 0)
      return false;
   return OrderSelect(ticket);
  }

void SnapshotExistingPositions(ulong &out[])
  {
   ArrayResize(out, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != RESSUP_AUTO_MAGIC)
         continue;
      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = ticket;
     }
  }

bool IsKnownPosition(const ulong ticket, const ulong &known[])
  {
   for(int i = 0; i < ArraySize(known); i++)
      if(known[i] == ticket)
         return true;
   return false;
  }

int FindFilledDirection(const ulong &known[])
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != RESSUP_AUTO_MAGIC)
         continue;
      if(IsKnownPosition(ticket, known))
         continue;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
     }
   return 0;
  }

// ---------------------------------------------------------------------------
// New: the state machine. Everything above this line is the script, unchanged
// in behaviour and retagged only in magic number and log prefix.
// ---------------------------------------------------------------------------

// Reads the two rail objects. False whenever no box is currently armed -- the
// normal state most of the time -- so callers must not log on a false return,
// or the log fills with one line per tick forever.
bool TryReadPair(double &res, double &sup)
  {
   return ReadLevel(InpResObjectName, InpManualRes, res) &&
          ReadLevel(InpSupObjectName, InpManualSup, sup) &&
          res > sup;
  }

// One placement attempt for a newly-seen (res, sup) pair. Mirrors the body of
// the script's OnStart() from the account gate through both PlacePending()
// calls -- everything after that (the poll loop) is now OnTick()'s job instead.
void TryPlaceOco(const double res, const double sup)
  {
   if(!ResSupAccountOk())
     {
      Print("RES-SUP OCO Auto: refused — real account with InpAllowLiveTrading = false.");
      return;
     }
   const bool live = B100IsRealAccount();
   if(live)
      Print("RES-SUP OCO Auto: *** LIVE ACCOUNT ", AccountInfoInteger(ACCOUNT_LOGIN),
            " — REAL MONEY. lots=", DoubleToString(InpLots, 2), " ***");
   else
      Print("RES-SUP OCO Auto: demo account ", AccountInfoInteger(ACCOUNT_LOGIN),
            "  lots=", DoubleToString(InpLots, 2));

   const double height = res - sup;
   const double offset = MathMax(_Point, InpOffsetPct * MathMax(height, _Point));
   const double buy_px  = res + offset;
   const double sell_px = sup - offset;

   double sl_buy  = buy_px  - height * (1.0 + MathMax(0.0, InpSlBufR));
   double sl_sell = sell_px + height * (1.0 + MathMax(0.0, InpSlBufR));
   sl_buy  = MathMin(sl_buy,  sup - MathMax(InpSlBufR, 0.0) * height);
   sl_sell = MathMax(sl_sell, res + MathMax(InpSlBufR, 0.0) * height);

   const double r_buy  = buy_px  - sl_buy;
   const double r_sell = sl_sell - sell_px;
   if(r_buy <= 0.0 || r_sell <= 0.0)
     {
      Print("RES-SUP OCO Auto: degenerate stop distance, refusing to place.");
      return;
     }
   const double tp_buy  = buy_px  + InpTp1R * r_buy;
   const double tp_sell = sell_px - InpTp1R * r_sell;

   Print("RES-SUP OCO Auto: RES=", DoubleToString(res, _Digits), " SUP=", DoubleToString(sup, _Digits),
         "  BUY ", DoubleToString(buy_px, _Digits), " SL ", DoubleToString(sl_buy, _Digits),
         " TP ", DoubleToString(tp_buy, _Digits),
         "  SELL ", DoubleToString(sell_px, _Digits), " SL ", DoubleToString(sl_sell, _Digits),
         " TP ", DoubleToString(tp_sell, _Digits));

   SnapshotExistingPositions(g_known);
   if(ArraySize(g_known) > 0)
      Print("RES-SUP OCO Auto: ", ArraySize(g_known),
            " position(s) already open under this magic — they will be ignored.");

   string err = "";
   ulong buy_tk = 0, sell_tk = 0;
   if(!PlacePending(ORDER_TYPE_BUY_STOP, buy_px, sl_buy, tp_buy, buy_tk, err))
     {
      Print("RES-SUP OCO Auto: BUY STOP failed — ", err);
      return;
     }
   if(!PlacePending(ORDER_TYPE_SELL_STOP, sell_px, sl_sell, tp_sell, sell_tk, err))
     {
      Print("RES-SUP OCO Auto: SELL STOP failed — ", err, " — cancelling the BUY leg");
      string cerr = "";
      if(!CancelTicket(buy_tk, cerr))
         Print("RES-SUP OCO Auto: WARNING — BUY STOP ticket=", buy_tk,
               " could not be cancelled (", cerr, "). Cancel it by hand now.");
      return;
     }
   Print("RES-SUP OCO Auto: armed. BUY ticket=", buy_tk, "  SELL ticket=", sell_tk,
         "  first fill cancels the other.");

   g_buy_tk   = buy_tk;
   g_sell_tk  = sell_tk;
   g_deadline = GetTickCount64() + (ulong)MathMax(InpTimeoutMinutes, 1) * 60000;
   g_state    = RESSUP_ARMED_PENDING;
  }

// One tick of monitoring an already-placed pair: fill+cancel, both-gone, or
// timeout. Identical logic to the script's poll loop, checked on every tick
// (BREAK100 ticks ~1/s, matching the script's 500ms cadence) instead of inside
// a blocking Sleep() loop, since an EA must never block OnTick.
void PollArmedPair(void)
  {
   const int dir = FindFilledDirection(g_known);
   if(dir != 0)
     {
      string cerr = "";
      const ulong other = (dir > 0) ? g_sell_tk : g_buy_tk;
      for(int attempt = 0; attempt < 10 && TicketIsPending(other); attempt++)
        {
         if(CancelTicket(other, cerr))
            break;
         Print("RES-SUP OCO Auto: sibling cancel failed (", cerr, ") — retrying");
        }
      if(TicketIsPending(other))
         Print("RES-SUP OCO Auto: WARNING — ", (dir > 0 ? "SELL" : "BUY"),
               " STOP ticket=", other, " IS STILL RESTING. Cancel it by hand now.");
      else
         Print("RES-SUP OCO Auto: ", (dir > 0 ? "BUY" : "SELL"), " filled — sibling cancelled.");
      g_state = RESSUP_IDLE;
      return;
     }
   if(!TicketIsPending(g_buy_tk) && !TicketIsPending(g_sell_tk))
     {
      Print("RES-SUP OCO Auto: both pendings gone with no fill under our magic — idle again.");
      g_state = RESSUP_IDLE;
      return;
     }
   if(GetTickCount64() >= g_deadline)
     {
      string terr = "";
      if(TicketIsPending(g_buy_tk) && !CancelTicket(g_buy_tk, terr))
         Print("RES-SUP OCO Auto: WARNING — BUY STOP ticket=", g_buy_tk,
               " survived the timeout cancel (", terr, "). Cancel it by hand.");
      if(TicketIsPending(g_sell_tk) && !CancelTicket(g_sell_tk, terr))
         Print("RES-SUP OCO Auto: WARNING — SELL STOP ticket=", g_sell_tk,
               " survived the timeout cancel (", terr, "). Cancel it by hand.");
      Print("RES-SUP OCO Auto: timed out after ", InpTimeoutMinutes, " minutes — idle again.");
      g_state = RESSUP_IDLE;
     }
  }

int OnInit(void)
  {
   g_state    = RESSUP_IDLE;
   g_last_res = -1.0;
   g_last_sup = -1.0;
   Print("RES-SUP OCO Auto: started. magic=", RESSUP_AUTO_MAGIC,
         "  InpAllowLiveTrading=", (InpAllowLiveTrading ? "true" : "false"),
         "  lots=", DoubleToString(InpLots, 2),
         " — watching '", InpResObjectName, "'/'", InpSupObjectName, "' for a new box.");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   // Deliberately does not cancel resting orders -- matches the manual script's
   // own "stopped by user — pendings left as-is" behaviour. Removing this EA
   // from the chart must not silently yank a live pending or position.
   if(g_state == RESSUP_ARMED_PENDING)
      Print("RES-SUP OCO Auto: stopping with an armed pair still outstanding "
            "(BUY ticket=", g_buy_tk, " SELL ticket=", g_sell_tk, ") — left as-is.");
   else
      Print("RES-SUP OCO Auto: stopped.");
  }

void OnTick(void)
  {
   if(g_state == RESSUP_ARMED_PENDING)
     {
      PollArmedPair();
      return;
     }

   double res = 0.0, sup = 0.0;
   if(!TryReadPair(res, sup))
      return;  // no box armed right now -- the normal idle state, stay quiet
   if(MathAbs(res - g_last_res) < _Point && MathAbs(sup - g_last_sup) < _Point)
      return;  // same pair already handled (placed, refused, or degenerate)

   // Mark handled regardless of outcome, BEFORE attempting -- one attempt per
   // snapshot, exactly like a human launching the script once per box.
   g_last_res = res;
   g_last_sup = sup;
   TryPlaceOco(res, sup);
  }
