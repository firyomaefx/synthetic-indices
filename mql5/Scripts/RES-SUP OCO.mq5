#property copyright "Break100 Box Trading"
#property version   "1.00"
#property script_show_inputs
#property description "Places a BUY STOP + SELL STOP OCO pair off the chart's RES/SUP rails,"
#property description "each with SL/TP already attached. Cancels the sibling on fill."
#property description "Not an EA — this is a Script: run it once per snapshot you want to act on."

// Reads the same RES/SUP rail objects "Break100 Box Trading.mq5" draws
// (B100BoxRail -> BOX_RES/BOX_SUP, Break100 Box Trading.mq5:2475-2476), so
// dropping this onto a chart that already has the EA's WATCH state showing
// RES/SUP needs no extra setup. Levels, SL and TP are all derived from those
// two chart prices — never arbitrary — using the same shape as the EA's own
// B100FillBoxLevels (Break100 Box Trading.mq5:1817-1870):
//
//   buy_stop  = RES + InpOffsetPct * height
//   sell_stop = SUP - InpOffsetPct * height
//   SL        = InpSlBufR box-heights beyond entry, clamped to the far rail
//   TP        = entry + InpTp1R * R
//
// A Script has no OnTick/OnTradeTransaction — OnStart() runs once and the
// script ends when it returns. To still cancel the sibling on a fill, this
// polls every 500ms inside OnStart() until one side fills, both are gone, or
// InpTimeoutMinutes elapses. Uses its own magic number, distinct from the
// main EA's B100_MAGIC (100165), so the EA's cleanup sweep and this script's
// fill can never cross-react if both are ever attached to the same symbol.
//
// SAFETY: running this is itself the arming gesture -- there is no separate
// "arm" step the way the always-on EA has one, because a Script only ever
// runs when a person deliberately launches it. It still refuses a real
// account unless explicitly permitted: same demo-or-allowlisted-live bar as
// the EA (Mode.mqh), never weaker.
//
// MANUAL TEST (demo account first, always):
//   1. Attach to a BREAK100 chart that already shows RES/SUP (either the main
//      EA's WATCH state, or two horizontal lines you name to match
//      InpResObjectName/InpSupObjectName).
//   2. Run with InpAllowLiveTrading=false on a demo account. Confirm both a
//      BUY STOP and a SELL STOP appear in the Trade tab, each already showing
//      a nonzero S/L and T/P.
//   3. Let one side fill (or move price in Strategy Tester). Confirm the
//      sibling pending is gone within ~1s and the script prints which side
//      filled, then exits.
//   4. Re-run per new snapshot; this script does not auto-rearm.

#include <Break100/Mode.mqh>
#include <Break100/DemoExec.mqh>   // B100ExecAccountOk, B100FreezePrice, B100StopsLevel,
                                    // B100DemoCancelTicket (ticket-scoped, no magic coupling)

#define RESSUP_MAGIC 100265        // distinct from B100_MAGIC (DemoExec.mqh:12)

input string InpResObjectName  = "B100_box_res";  // Chart object to read RES (resistance) from
input string InpSupObjectName  = "B100_box_sup";  // Chart object to read SUP (support) from
input double InpManualRes      = 0.0;             // Used only if the RES object isn't found (0 = none)
input double InpManualSup      = 0.0;             // Used only if the SUP object isn't found (0 = none)
input double InpOffsetPct      = 0.02;            // Stop offset beyond RES/SUP, as a fraction of height
input double InpSlBufR         = 0.15;            // SL beyond opposite rail, in box heights
input double InpTp1R           = 1.0;             // TP as a multiple of the stop distance (R)
input double InpLots           = 0.01;            // Lot size per leg — change to suit your account
input int    InpTimeoutMinutes = 240;             // Cancel both and exit if neither fills in time
input bool   InpAllowLiveTrading = false;         // Gate: permit a real account at all. Real money.
input long   InpLiveAccountLogin = 0;             // Gate: must equal this account's login exactly

bool ResSupAccountOk(void)
  {
   if(B100IsDemoAccount())
      return true;
   if(!B100IsRealAccount())
      return false;
   return InpAllowLiveTrading && InpLiveAccountLogin != 0 &&
          InpLiveAccountLogin == (long)AccountInfoInteger(ACCOUNT_LOGIN);
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

// Local placement wrapper, modeled on B100DemoPlacePending (DemoExec.mqh:269-349)
// but tagged with RESSUP_MAGIC instead of the EA's shared B100_MAGIC.
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
   req.magic        = RESSUP_MAGIC;
   req.comment      = "RESSUP-OCO";
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

// Any open position under our magic on this symbol -> the fill we're waiting for.
int FindFilledDirection(void)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != RESSUP_MAGIC)
         continue;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
     }
   return 0;
  }

void OnStart(void)
  {
   if(!ResSupAccountOk())
     {
      Print("RES-SUP OCO: refused — not a demo account and LIVE gates not satisfied.");
      return;
     }

   double res = 0.0, sup = 0.0;
   if(!ReadLevel(InpResObjectName, InpManualRes, res) ||
      !ReadLevel(InpSupObjectName, InpManualSup, sup) ||
      res <= sup)
     {
      Print("RES-SUP OCO: could not read valid RES/SUP levels (object missing and no manual price set).");
      return;
     }

   const double height = res - sup;
   const double offset = MathMax(_Point, InpOffsetPct * MathMax(height, _Point));
   const double buy_px  = res + offset;
   const double sell_px = sup - offset;

   double sl_buy  = buy_px  - height * (1.0 + MathMax(0.0, InpSlBufR));
   double sl_sell = sell_px + height * (1.0 + MathMax(0.0, InpSlBufR));
   // Never let the stop sit inside the opposite rail.
   sl_buy  = MathMin(sl_buy,  sup - MathMax(InpSlBufR, 0.0) * height);
   sl_sell = MathMax(sl_sell, res + MathMax(InpSlBufR, 0.0) * height);

   const double r_buy  = buy_px  - sl_buy;
   const double r_sell = sl_sell - sell_px;
   if(r_buy <= 0.0 || r_sell <= 0.0)
     {
      Print("RES-SUP OCO: degenerate stop distance, refusing to place.");
      return;
     }
   const double tp_buy  = buy_px  + InpTp1R * r_buy;
   const double tp_sell = sell_px - InpTp1R * r_sell;

   Print("RES-SUP OCO: RES=", DoubleToString(res, _Digits), " SUP=", DoubleToString(sup, _Digits),
         "  BUY ", DoubleToString(buy_px, _Digits), " SL ", DoubleToString(sl_buy, _Digits),
         " TP ", DoubleToString(tp_buy, _Digits),
         "  SELL ", DoubleToString(sell_px, _Digits), " SL ", DoubleToString(sl_sell, _Digits),
         " TP ", DoubleToString(tp_sell, _Digits));

   string err = "";
   ulong buy_tk = 0, sell_tk = 0;
   if(!PlacePending(ORDER_TYPE_BUY_STOP, buy_px, sl_buy, tp_buy, buy_tk, err))
     {
      Print("RES-SUP OCO: BUY STOP failed — ", err);
      return;
     }
   if(!PlacePending(ORDER_TYPE_SELL_STOP, sell_px, sl_sell, tp_sell, sell_tk, err))
     {
      Print("RES-SUP OCO: SELL STOP failed — ", err, " — cancelling the BUY leg");
      string cerr = "";
      B100DemoCancelTicket(buy_tk, cerr);
      return;
     }
   Print("RES-SUP OCO: armed. BUY ticket=", buy_tk, "  SELL ticket=", sell_tk,
         "  first fill cancels the other.");

   const ulong deadline = GetTickCount64() + (ulong)MathMax(InpTimeoutMinutes, 1) * 60000;
   while(!IsStopped())
     {
      const int dir = FindFilledDirection();
      if(dir != 0)
        {
         string cerr = "";
         const ulong other = (dir > 0) ? sell_tk : buy_tk;
         if(TicketIsPending(other))
            B100DemoCancelTicket(other, cerr);
         Print("RES-SUP OCO: ", (dir > 0 ? "BUY" : "SELL"), " filled — sibling cancelled.");
         return;
        }
      if(!TicketIsPending(buy_tk) && !TicketIsPending(sell_tk))
        {
         Print("RES-SUP OCO: both pendings gone with no fill under our magic — exiting.");
         return;
        }
      if(GetTickCount64() >= deadline)
        {
         string terr = "";
         if(TicketIsPending(buy_tk))
            B100DemoCancelTicket(buy_tk, terr);
         if(TicketIsPending(sell_tk))
            B100DemoCancelTicket(sell_tk, terr);
         Print("RES-SUP OCO: timed out after ", InpTimeoutMinutes, " minutes — both cancelled.");
         return;
        }
      Sleep(500);
     }
   Print("RES-SUP OCO: stopped by user — pendings left as-is, check the Trade tab.");
  }
