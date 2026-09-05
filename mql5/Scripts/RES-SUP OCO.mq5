#property copyright "Break100 Box Trading"
#property version   "1.04"
#property script_show_inputs
#property description "Places a BUY STOP + SELL STOP OCO pair off the chart's RES/SUP rails,"
#property description "each with SL/TP already attached. Cancels the sibling on fill."
#property description "Not an EA — this is a Script: run it once per snapshot you want to act on."
#property description "1.01 LIVE ACCOUNTS ENABLED. 1.02 per-leg broker stops-level check."
#property description "1.03 late market entry on a recent breach."
#property description "1.04 LIMIT retrace at the alert price first."

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
// *** THIS TRADES REAL MONEY ON A LIVE ACCOUNT. ***
// InpAllowLiveTrading defaults to TRUE, at the owner's explicit instruction
// (2026-09-04, DECISION_LOG D-007). There is no account-number allowlist and no
// chart arm button: launching the script IS the arming gesture, because a Script
// only ever runs when a person deliberately drags it onto a chart. Set
// InpAllowLiveTrading = false in the input dialog to make any live run a no-op.
// The input dialog appears on every single launch, so the current setting is
// always visible before anything is sent.
//
// Read this before running it on a live account: the strategy this places orders
// for has NO MEASURED EDGE. research/BACKTEST_RESULTS.md, over 3.56M ticks and 41
// days, puts the shipped baseline at -4.90% ROI and -0.164R expectancy, with the
// best of 20 configurations reaching t=+0.12 against the ~2.45 needed to clear
// the trial-count bar. The 46.7% win rate is what spread geometry predicts on a
// driftless walk (46.25%). Nothing here is a profit claim.
//
// MANUAL TEST (demo account first, always):
//   1. Attach to a BREAK100 chart that already shows RES/SUP (either the main
//      EA's WATCH state, or two horizontal lines you name to match
//      InpResObjectName/InpSupObjectName).
//   2. Run it on a DEMO account first. Confirm both a BUY STOP and a SELL STOP
//      appear in the Trade tab, each already showing a nonzero S/L and T/P.
//   3. Let one side fill (or move price in Strategy Tester). Confirm the
//      sibling pending is gone within ~1s and the script prints which side
//      filled, then exits.
//   4. Only then repeat on the live account, at InpLots you can afford to lose.
//   5. Re-run per new snapshot; this script does not auto-rearm.

#include <Break100/Mode.mqh>       // B100IsDemoAccount / B100IsRealAccount
#include <Break100/DemoExec.mqh>   // B100FreezePrice (pure; tick-size normalisation)

// How far back LevelBreachAgeMs looks for the first breach. Must be comfortably
// wider than InpLateEntrySecs: a level that broke before this window began
// reports its age as the window start, which correctly ages out as "too late".
#define BREACH_WINDOW_SECS 60

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
input int    InpRetraceWaitSecs = 20;             // On a breach, wait this long for price to pull back to the alert level (0=off, go straight to late entry)
input int    InpLateEntrySecs  = 7;               // Take a breached level at market if it broke this recently (0=off)
input double InpLateEntryMaxR  = 0.25;            // ...but only if the late price costs under this much extra R
input bool   InpAllowLiveTrading = true;          // REAL MONEY on a live account. Set false to disable.

bool ResSupAccountOk(void)
  {
   if(B100IsDemoAccount())
      return true;
   if(!B100IsRealAccount())
      return false;
   return InpAllowLiveTrading;
  }

// Self-contained cancel. Deliberately NOT B100DemoCancelTicket: that one gates on
// B100ExecAccountOk(), which for a real account requires DemoExec.mqh's
// g_b100_exec_live_ok global — a flag the EA sets from its chart arm button and
// that a Script never sets. Routing cancels through it would have failed every
// sibling cancel on a live account with ACCOUNT_NOT_PERMITTED, leaving the losing
// side's stop order resting on the broker after a fill. The account decision is
// made once, up front, in ResSupAccountOk(); nothing below re-litigates it.
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
   Print("RES-SUP OCO: cancelled ticket=", ticket);
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

// Local placement wrapper, modeled on B100DemoPlacePending (DemoExec.mqh:269-349)
// but tagged with RESSUP_MAGIC instead of the EA's shared B100_MAGIC. Handles
// both STOP and LIMIT pendings -- the SL side check is about buy-vs-sell, not
// stop-vs-limit, since a long's stop sits below entry either way.
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
   const bool   isBuy = (typ == ORDER_TYPE_BUY_STOP || typ == ORDER_TYPE_BUY_LIMIT);
   if(isBuy && slx >= px)
     {
      err = "SL_NOT_BELOW_BUY";
      return false;
     }
   if(!isBuy && slx <= px)
     {
      err = "SL_NOT_ABOVE_SELL";
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

// Positions already open under our magic BEFORE this run places anything. An
// earlier run's position can still be running to its TP/SL when the next
// snapshot is traded — the intended workflow is one launch per snapshot. Without
// this, the poll loop below would see that older position, mistake it for its
// own fill, and immediately cancel one of the two legs it had just placed.
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
      if((long)PositionGetInteger(POSITION_MAGIC) != RESSUP_MAGIC)
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

// A position under our magic that did NOT exist before this run -> our fill.
int FindFilledDirection(const ulong &known[])
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
      if(IsKnownPosition(ticket, known))
         continue;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
     }
   return 0;
  }

// How long ago price FIRST traded through `level` in the breakout direction,
// in milliseconds, or -1 if it never did inside the search window.
//
// A stop order that price has already run past cannot be placed at all -- the
// server rejects a stop sitting on the wrong side of the market. The strategy's
// signal has still fired, though, so the real choice is "enter late at market"
// or "skip", and that turns on HOW late. Scanning forward from the oldest tick
// in the window and stopping at the first breach is what makes a level that
// broke long ago report as old rather than fresh: if price has been through it
// for minutes, its first breach inside the window is the window's own start,
// which ages out immediately. Timestamps come from the ticks themselves rather
// than TimeCurrent(), so this stays millisecond-accurate.
long LevelBreachAgeMs(const double level, const int dir)
  {
   MqlTick ticks[];
   const datetime from = TimeCurrent() - BREACH_WINDOW_SECS;
   const int n = CopyTicks(_Symbol, ticks, COPY_TICKS_INFO, (ulong)from * 1000, 0);
   if(n <= 0)
      return -1;
   for(int i = 0; i < n; i++)
     {
      const bool breached = (dir > 0) ? (ticks[i].ask >= level) : (ticks[i].bid <= level);
      if(breached)
         return (long)ticks[n - 1].time_msc - (long)ticks[i].time_msc;
     }
   return -1;
  }

// Market entry for a level that already broke, carrying the SAME SL and TP the
// pending leg would have used -- that is what "matches the Telegram alert".
// Tagged with RESSUP_MAGIC like the pending legs so SnapshotExistingPositions
// and FindFilledDirection still recognise the result as ours.
bool PlaceMarket(const ENUM_ORDER_TYPE typ, const double sl, const double tp,
                 ulong &order_ticket, string &err)
  {
   err = "";
   order_ticket = 0;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      err = "TRADE_DISABLED";
      return false;
     }
   if(InpLots <= 0.0 || sl <= 0.0)
     {
      err = "SL_OR_LOTS_INVALID";
      return false;
     }
   const double px  = (typ == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double slx = B100FreezePrice(sl);
   const double tpx = (tp > 0.0) ? B100FreezePrice(tp) : 0.0;
   if(!B100FarEnough(px, slx) || (tpx > 0.0 && !B100FarEnough(px, tpx)))
     {
      err = "SL_OR_TP_INSIDE_STOPS_LEVEL";
      return false;
     }
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = InpLots;
   req.type      = typ;
   req.price     = px;
   req.sl        = slx;
   req.tp        = tpx;
   req.deviation = 20;
   req.magic     = RESSUP_MAGIC;
   req.comment   = "RESSUP-OCO-LATE";
   // Market orders reject outright on the wrong filling mode, and it differs by
   // broker -- ask the symbol instead of assuming the pending legs' RETURN.
   const long fill = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_FOK) != 0)
      req.type_filling = ORDER_FILLING_FOK;
   else if((fill & SYMBOL_FILLING_IOC) != 0)
      req.type_filling = ORDER_FILLING_IOC;
   else
      req.type_filling = ORDER_FILLING_RETURN;
   ResetLastError();
   if(!OrderSend(req, res))
     {
      err = "MARKET_FAIL " + IntegerToString((int)res.retcode) +
            " last=" + IntegerToString(GetLastError());
      return false;
     }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
     {
      err = "MARKET_RETCODE=" + IntegerToString((int)res.retcode);
      return false;
     }
   order_ticket = res.order;
   return true;
  }

// After a breach, price often pulls back toward the broken rail before
// continuing -- that pullback fills a LIMIT order at the exact alert price,
// with no spread paid going through and no chase. This tries that first,
// before the instant-market fallback: BUY_LIMIT/SELL_LIMIT at `level` (the
// same buy_px/sell_px the alert published, so "matches the Telegram alert"
// is literal, not approximate), same SL/TP as the pending leg would have
// used. `known` must be snapshotted by the caller BEFORE this is called, so
// FindFilledDirection can tell this fill from a pre-existing position.
//
// Returns true only on an actual fill. A timeout cancels the resting limit
// and returns false -- the caller decides what "no retrace" means (currently:
// fall through to the existing late-market-entry evaluation, using whatever
// price the market is at by then).
bool TryRetraceEntry(const int dir, const double level, const double sl, const double tp,
                     const ulong &known[])
  {
   string err = "";
   ulong  ticket = 0;
   const ENUM_ORDER_TYPE typ = (dir > 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   if(!PlacePending(typ, level, sl, tp, ticket, err))
     {
      Print("RES-SUP OCO: retrace limit failed to place — ", err, " — trying late entry instead.");
      return false;
     }
   Print("RES-SUP OCO: waiting up to ", InpRetraceWaitSecs, "s for a retrace fill at ",
         DoubleToString(level, _Digits), "  ticket=", ticket);
   const ulong deadline = GetTickCount64() + (ulong)MathMax(InpRetraceWaitSecs, 1) * 1000;
   while(!IsStopped())
     {
      if(FindFilledDirection(known) != 0)
        {
         Print("RES-SUP OCO: retrace filled at ", DoubleToString(level, _Digits), " — best price, no chase.");
         return true;
        }
      if(!TicketIsPending(ticket))
        {
         Print("RES-SUP OCO: retrace limit ticket=", ticket,
               " is gone with no fill under our magic — trying late entry instead.");
         return false;
        }
      if(GetTickCount64() >= deadline)
        {
         string cerr = "";
         if(!CancelTicket(ticket, cerr))
            Print("RES-SUP OCO: WARNING — retrace limit ticket=", ticket,
                  " could not be cancelled (", cerr, "). Cancel it by hand now.");
         Print("RES-SUP OCO: no retrace within ", InpRetraceWaitSecs, "s — trying late entry instead.");
         return false;
        }
      Sleep(200);
     }
   // Stopped by the user mid-wait. Leave the limit resting rather than guess
   // whether they wanted it cancelled -- same "pendings left as-is" contract
   // OnStart's own poll loop already documents.
   Print("RES-SUP OCO: stopped by user during the retrace wait — limit ticket=", ticket, " left as-is.");
   return false;
  }

void OnStart(void)
  {
   if(!ResSupAccountOk())
     {
      Print("RES-SUP OCO: refused — real account with InpAllowLiveTrading = false.");
      return;
     }
   const bool live = B100IsRealAccount();
   if(live)
      Print("RES-SUP OCO: *** LIVE ACCOUNT ", AccountInfoInteger(ACCOUNT_LOGIN),
            " — REAL MONEY. lots=", DoubleToString(InpLots, 2), " ***");
   else
      Print("RES-SUP OCO: demo account ", AccountInfoInteger(ACCOUNT_LOGIN),
            "  lots=", DoubleToString(InpLots, 2));

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

   // Broker minimum distance for any pending/SL/TP. BREAK100 reports
   // SYMBOL_TRADE_STOPS_LEVEL = 1000 points = 10.00 price units. The EA has
   // honoured this since it placed its own pendings (Break100 Box Trading.mq5:
   // 1520-1541, logged as SKIP_STOPS_LEVEL); this script never did, so a rail
   // sitting within that distance of the market produced an order the server
   // rejects outright with retcode 10016. Read live via B100StopsLevel() rather
   // than hardcoded -- the broker can change it, and 0 means "no minimum".
   //
   // Each leg is judged on its own. Previously the BUY leg was sent first and a
   // failure returned immediately, so a BUY blocked by this distance also
   // suppressed a SELL that was perfectly placeable -- which is exactly the case
   // when price is hugging the RES rail, the moment you most want to be armed.
   const double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double need = B100StopsLevel();

   // Each stop leg is in exactly one of three states, and only the first can be
   // sent as a pending order at all:
   //   placeable  entry is still the correct side of market by at least `need`
   //   breached   price has already traded through the entry. A pending stop on
   //              the wrong side of market is rejected outright -- but the
   //              breakout this leg was waiting for HAS happened, so it becomes
   //              a late-entry candidate rather than a dead leg.
   //   too close  correct side, but nearer than `need`. The server rejects it
   //              and the move has not happened, so there is nothing to enter
   //              late either. Skip and re-run once price separates.
   // Testing the side explicitly matters: B100FarEnough is a distance, so on its
   // own it happily calls a BUY STOP 20 points BELOW the market "far enough".
   const bool buy_sl_tp_ok  = B100FarEnough(buy_px, sl_buy) &&
                              (tp_buy  <= 0.0 || B100FarEnough(buy_px, tp_buy));
   const bool sell_sl_tp_ok = B100FarEnough(sell_px, sl_sell) &&
                              (tp_sell <= 0.0 || B100FarEnough(sell_px, tp_sell));
   const bool buy_breached  = (ask >= buy_px);
   const bool sell_breached = (bid <= sell_px);
   const bool buy_ok  = !buy_breached  && ((buy_px - ask) >= need) && buy_sl_tp_ok;
   const bool sell_ok = !sell_breached && ((bid - sell_px) >= need) && sell_sl_tp_ok;

   // Baseline the positions that already exist under our magic, BEFORE placing
   // anything -- including the retrace attempt below -- so every poll loop in
   // this run can tell our own fill from a still-running position an earlier
   // launch left open.
   ulong known[];
   SnapshotExistingPositions(known);
   if(ArraySize(known) > 0)
      Print("RES-SUP OCO: ", ArraySize(known),
            " position(s) already open under this magic — they will be ignored.");

   // Retrace entry. Exactly one rail breaching is the case a pullback can
   // actually happen for -- both at once (spread wider than the box) or
   // neither leaves nothing to wait for. This runs BEFORE the late-entry
   // evaluation below and, on success, skips it entirely: a retrace fill IS
   // the entry, at a strictly better price than late entry could ever get
   // (exactly the alert level, not "close to it").
   if(InpRetraceWaitSecs > 0 && (buy_breached != sell_breached))
     {
      const int    dir   = buy_breached ? 1 : -1;
      const double level = buy_breached ? buy_px : sell_px;
      const double sl    = buy_breached ? sl_buy : sl_sell;
      const double tp    = buy_breached ? tp_buy : tp_sell;
      if(TryRetraceEntry(dir, level, sl, tp, known))
         return;
      if(IsStopped())
         return;   // user cancelled mid-wait -- do not fall through to late entry
     }

   // Late entry. A breakout at most InpLateEntrySecs old is still worth taking
   // at market, but only if the price now is close to the level the Telegram
   // alert published -- capped at InpLateEntryMaxR of the planned risk. The SL
   // stays where the box put it, so paying up without that cap would silently
   // turn a 1R trade into a 1.5R one on the same stop. Deliberately re-reads
   // ask/bid rather than reusing the values from before the retrace wait --
   // that wait can run up to InpRetraceWaitSecs, and stale prices there would
   // silently misjudge both the age and the distance-past-level checks below.
   const double ask2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid2 = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    late_dir = 0;
   double late_sl  = 0.0, late_tp = 0.0;
   string late_why = "";
   if(InpLateEntrySecs > 0 && buy_breached && sell_breached)
      late_why = "both rails are breached at once (spread wider than the box) — refusing";
   else if(InpLateEntrySecs > 0 && (buy_breached || sell_breached))
     {
      const int    dir    = buy_breached ? 1 : -1;
      const double level  = buy_breached ? buy_px : sell_px;
      const double now_px = buy_breached ? ask2   : bid2;
      const double extra  = MathAbs(now_px - level);
      const double budget = MathMax(0.0, InpLateEntryMaxR) * (buy_breached ? r_buy : r_sell);
      const bool   sltp   = buy_breached ? buy_sl_tp_ok : sell_sl_tp_ok;
      const long   age    = LevelBreachAgeMs(level, dir);
      const string side   = (dir > 0) ? "BUY" : "SELL";
      if(age < 0)
         late_why = side + " broke before the " + IntegerToString(BREACH_WINDOW_SECS) +
                    "s look-back — too late";
      else if(age > (long)InpLateEntrySecs * 1000)
         late_why = side + " broke " + DoubleToString((double)age / 1000.0, 1) +
                    "s ago, over the " + IntegerToString(InpLateEntrySecs) + "s budget";
      else if(extra > budget)
         late_why = side + " is " + DoubleToString(extra, _Digits) +
                    " past the alert level, over the " + DoubleToString(budget, _Digits) +
                    " (" + DoubleToString(InpLateEntryMaxR, 2) + "R) budget";
      else if(!sltp)
         late_why = side + " SL/TP would sit inside the broker stops level";
      else
        {
         late_dir = dir;
         late_sl  = buy_breached ? sl_buy : sl_sell;
         late_tp  = buy_breached ? tp_buy : tp_sell;
         Print("RES-SUP OCO: ", side, " broke ", DoubleToString((double)age / 1000.0, 1),
               "s ago, ", DoubleToString(extra, _Digits), " past the alert level — taking it late.");
        }
     }

   if(!buy_ok && !buy_breached)
      Print("RES-SUP OCO: BUY leg skipped — inside broker stops level ",
            DoubleToString(need, _Digits), " (entry ", DoubleToString(buy_px, _Digits),
            " vs ask ", DoubleToString(ask, _Digits), ")");
   if(!sell_ok && !sell_breached)
      Print("RES-SUP OCO: SELL leg skipped — inside broker stops level ",
            DoubleToString(need, _Digits), " (entry ", DoubleToString(sell_px, _Digits),
            " vs bid ", DoubleToString(bid, _Digits), ")");
   if(late_why != "")
      Print("RES-SUP OCO: no late entry — ", late_why, ".");
   if(!buy_ok && !sell_ok && late_dir == 0)
     {
      Print("RES-SUP OCO: nothing placeable — no pending leg is valid and no late ",
            "entry qualifies. Re-run on the next box, or once price sits back inside this one.");
      return;
     }

   string err = "";

   // A late market entry IS the fill, so it resolves the OCO by itself and the
   // opposite leg is deliberately never sent. Placing it anyway would leave a
   // resting stop behind an already-open position — a hedge, not an OCO.
   if(late_dir != 0)
     {
      ulong late_tk = 0;
      const double level  = (late_dir > 0) ? buy_px : sell_px;
      const double px_now = (late_dir > 0) ? ask2   : bid2;
      if(!PlaceMarket((late_dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                      late_sl, late_tp, late_tk, err))
        {
         Print("RES-SUP OCO: late ", (late_dir > 0 ? "BUY" : "SELL"),
               " at market failed — ", err);
         return;
        }
      Print("RES-SUP OCO: LATE ", (late_dir > 0 ? "BUY" : "SELL"), " at market ~",
            DoubleToString(px_now, _Digits), "  alert level ", DoubleToString(level, _Digits),
            "  SL ", DoubleToString(late_sl, _Digits), "  TP ", DoubleToString(late_tp, _Digits),
            "  ticket=", late_tk,
            ". Opposite leg not placed — this fill resolves the OCO.");
      return;
     }

   ulong buy_tk = 0, sell_tk = 0;
   if(buy_ok && !PlacePending(ORDER_TYPE_BUY_STOP, buy_px, sl_buy, tp_buy, buy_tk, err))
     {
      Print("RES-SUP OCO: BUY STOP failed — ", err);
      buy_tk = 0;
     }
   if(sell_ok && !PlacePending(ORDER_TYPE_SELL_STOP, sell_px, sl_sell, tp_sell, sell_tk, err))
     {
      Print("RES-SUP OCO: SELL STOP failed — ", err);
      sell_tk = 0;
     }

   // A two-sided arm that half-failed is still rolled back, exactly as before:
   // an OCO reduced to one leg by an unexpected send failure is a directional
   // bet the caller never asked for. A one-sided arm is only ever entered
   // deliberately -- when the stops level ruled the other leg out above, before
   // anything was sent.
   if(buy_ok && sell_ok && ((buy_tk == 0) != (sell_tk == 0)))
     {
      const ulong orphan = (buy_tk != 0) ? buy_tk : sell_tk;
      Print("RES-SUP OCO: only one leg of a two-sided arm was accepted — cancelling it.");
      string cerr = "";
      if(!CancelTicket(orphan, cerr))
         Print("RES-SUP OCO: WARNING — ticket=", orphan,
               " could not be cancelled (", cerr, "). Cancel it by hand now.");
      return;
     }
   if(buy_tk == 0 && sell_tk == 0)
     {
      Print("RES-SUP OCO: no legs placed — nothing to monitor.");
      return;
     }
   if(buy_tk != 0 && sell_tk != 0)
      Print("RES-SUP OCO: armed. BUY ticket=", buy_tk, "  SELL ticket=", sell_tk,
            "  first fill cancels the other.");
   else
      Print("RES-SUP OCO: armed ONE-SIDED — ", (buy_tk != 0 ? "BUY" : "SELL"),
            " ticket=", (buy_tk != 0 ? buy_tk : sell_tk),
            ". The other leg was inside the broker stops level, so there is no",
            " sibling to cancel on fill.");

   const ulong deadline = GetTickCount64() + (ulong)MathMax(InpTimeoutMinutes, 1) * 60000;
   while(!IsStopped())
     {
      const int dir = FindFilledDirection(known);
      if(dir != 0)
        {
         string cerr = "";
         const ulong other = (dir > 0) ? sell_tk : buy_tk;
         // Do not report success on a failed cancel. An uncancelled opposite stop
         // is an unintended second position waiting for the next spike, so retry
         // rather than exit quietly, and say so plainly if it will not go.
         for(int attempt = 0; attempt < 10 && TicketIsPending(other); attempt++)
           {
            if(CancelTicket(other, cerr))
               break;
            Print("RES-SUP OCO: sibling cancel failed (", cerr, ") — retrying");
            Sleep(500);
           }
         if(TicketIsPending(other))
            Print("RES-SUP OCO: WARNING — ", (dir > 0 ? "SELL" : "BUY"),
                  " STOP ticket=", other, " IS STILL RESTING. Cancel it by hand now.");
         else if(other == 0)
            Print("RES-SUP OCO: ", (dir > 0 ? "BUY" : "SELL"),
                  " filled — one-sided arm, no sibling to cancel.");
         else
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
         if(TicketIsPending(buy_tk) && !CancelTicket(buy_tk, terr))
            Print("RES-SUP OCO: WARNING — BUY STOP ticket=", buy_tk,
                  " survived the timeout cancel (", terr, "). Cancel it by hand.");
         if(TicketIsPending(sell_tk) && !CancelTicket(sell_tk, terr))
            Print("RES-SUP OCO: WARNING — SELL STOP ticket=", sell_tk,
                  " survived the timeout cancel (", terr, "). Cancel it by hand.");
         Print("RES-SUP OCO: timed out after ", InpTimeoutMinutes, " minutes.");
         return;
        }
      Sleep(500);
     }
   Print("RES-SUP OCO: stopped by user — pendings left as-is, check the Trade tab.");
  }
