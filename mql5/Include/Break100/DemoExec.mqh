#ifndef BREAK100_DEMOEXEC_MQH
#define BREAK100_DEMOEXEC_MQH

// Execution adapter. OrderSend only after Mode permits.
//
// Historically this refused any non-demo account outright. With the LIVE gate in
// Mode.mqh that second check would silently swallow every live order while the
// chart button reported ARMED, so the account test now consults a flag the EA
// sets from B100LiveArmed(). It defaults false: nothing here reaches a real
// account unless the EA explicitly says the full LIVE gate chain passed.

#define B100_MAGIC 100165

bool g_b100_exec_live_ok = false;

bool B100ExecAccountOk(void)
  {
   return B100IsDemoAccount() || (g_b100_exec_live_ok && B100IsRealAccount());
  }

// Broker minimum distance for any pending/SL/TP, in price units.
// BREAK100 reports SYMBOL_TRADE_STOPS_LEVEL = 1000 points = 10.00.
double B100StopsLevel(void)
  {
   const long pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (pts > 0) ? (double)pts * _Point : 0.0;
  }

bool B100FarEnough(const double a, const double b)
  {
   const double need = B100StopsLevel();
   return (need <= 0.0) || (MathAbs(a - b) >= need);
  }

double B100FreezePrice(const double px);   // defined below

// Re-anchor a filled position's stop to a fixed distance from its ACTUAL fill.
// A gapped entry otherwise leaves the stop where the box put it, so the real
// risk exceeds the amount the position was sized for.
bool B100ModifyPositionSl(const ulong ticket, const double sl, const double tp, string &err)
  {
   err = "";
   if(!PositionSelectByTicket(ticket))
     {
      err = "POSITION_GONE";
      return false;
     }
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = _Symbol;
   req.position = ticket;
   req.sl       = B100FreezePrice(sl);
   req.tp       = (tp > 0.0) ? B100FreezePrice(tp) : 0.0;
   ResetLastError();
   if(!OrderSend(req, res) ||
      (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
     {
      err = "SLTP_FAIL " + IntegerToString((int)res.retcode) +
            " last=" + IntegerToString(GetLastError());
      return false;
     }
   return true;
  }

bool B100DemoFilling(ENUM_ORDER_TYPE_FILLING &fill)
  {
   const int mode = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
     {
      fill = ORDER_FILLING_FOK;
      return true;
     }
   if((mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
     {
      fill = ORDER_FILLING_IOC;
      return true;
     }
   fill = ORDER_FILLING_RETURN;
   return true;
  }

int B100CountMagicPositions(void)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != B100_MAGIC)
         continue;
      n++;
     }
   return n;
  }

int B100CountMagicPendings(void)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != B100_MAGIC)
         continue;
      n++;
     }
   return n;
  }

double B100FreezePrice(const double px)
  {
   const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      return NormalizeDouble(px, _Digits);
   return NormalizeDouble(MathRound(px / tick) * tick, _Digits);
  }

bool B100DemoSend(const int dir,
                  const double sl,
                  const double tp,
                  const double lots,
                  const string signal_id,
                  string &err)
  {
   err = "";
   if(!B100ExecAccountOk())
     {
      err = "ACCOUNT_NOT_PERMITTED";
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      err = "TERMINAL_TRADE_DISABLED";
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      err = "EA_TRADE_DISABLED";
      return false;
     }
   if(dir != 1 && dir != -1)
     {
      err = "BAD_DIR";
      return false;
     }
   if(lots <= 0.0 || sl <= 0.0)
     {
      err = "SL_OR_LOTS_INVALID";
      return false;
     }
   if(B100CountMagicPositions() > 0)
     {
      err = "MAX_POSITION_REACHED";
      return false;
     }

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double price = (dir > 0) ? ask : bid;
   if(dir > 0 && sl >= price)
     {
      err = "SL_NOT_BELOW_ENTRY";
      return false;
     }
   if(dir < 0 && sl <= price)
     {
      err = "SL_NOT_ABOVE_ENTRY";
      return false;
     }

   ENUM_ORDER_TYPE_FILLING fill;
   B100DemoFilling(fill);

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = lots;
   req.type         = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price        = price;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = 40;
   req.magic        = B100_MAGIC;
   req.comment      = signal_id;
   req.type_filling = fill;
   req.type_time    = ORDER_TIME_GTC;

   ResetLastError();
   if(!OrderSend(req, res))
     {
      err = "ORDERSEND_FAIL retcode=" + IntegerToString((int)res.retcode) +
            " last=" + IntegerToString(GetLastError());
      Print("B100 DemoExec FAIL ", err, " ", signal_id);
      return false;
     }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED &&
      res.retcode != TRADE_RETCODE_DONE_PARTIAL)
     {
      err = "ORDERSEND_RETCODE=" + IntegerToString((int)res.retcode);
      Print("B100 DemoExec RET ", err, " ", signal_id);
      return false;
     }
   Print("B100 DemoExec OK ticket=", res.order, " deal=", res.deal,
         " ", signal_id, " lots=", DoubleToString(lots, 2),
         " sl=", DoubleToString(sl, _Digits),
         " tp=", DoubleToString(tp, _Digits));
   return true;
  }

bool B100DemoCancelTicket(const ulong ticket, string &err)
  {
   err = "";
   if(ticket == 0)
      return true;
   if(!B100ExecAccountOk())
     {
      err = "ACCOUNT_NOT_PERMITTED";
      return false;
     }
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;
   ResetLastError();
   if(!OrderSend(req, res))
     {
      err = "CANCEL_FAIL " + IntegerToString((int)res.retcode);
      return false;
     }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
     {
      err = "CANCEL_RETCODE=" + IntegerToString((int)res.retcode);
      return false;
     }
   Print("B100 pending cancel ticket=", ticket);
   return true;
  }

void B100DemoCancelAllPendings(void)
  {
   string err = "";
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != B100_MAGIC)
         continue;
      B100DemoCancelTicket(ticket, err);
     }
  }

bool B100DemoPlacePending(const ENUM_ORDER_TYPE typ,
                          const double price,
                          const double sl,
                          const double tp,
                          const double lots,
                          const string signal_id,
                          ulong &ticket,
                          string &err)
  {
   err = "";
   ticket = 0;
   if(!B100ExecAccountOk())
     {
      err = "ACCOUNT_NOT_PERMITTED";
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      err = "TRADE_DISABLED";
      return false;
     }
   if(lots <= 0.0 || price <= 0.0 || sl <= 0.0)
     {
      err = "SL_OR_LOTS_INVALID";
      return false;
     }
   if(typ != ORDER_TYPE_BUY_STOP && typ != ORDER_TYPE_SELL_STOP)
     {
      err = "PENDING_TYPE";
      return false;
     }
   const double px = B100FreezePrice(price);
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
   req.volume       = lots;
   req.type         = typ;
   req.price        = px;
   req.sl           = slx;
   req.tp           = tpx;
   req.magic        = B100_MAGIC;
   req.comment      = signal_id;
   req.type_time    = ORDER_TIME_GTC;
   req.type_filling = ORDER_FILLING_RETURN;
   ResetLastError();
   if(!OrderSend(req, res))
     {
      err = "PENDING_FAIL " + IntegerToString((int)res.retcode) +
            " last=" + IntegerToString(GetLastError());
      Print("B100 pending FAIL ", err, " ", EnumToString(typ), " @", DoubleToString(px, _Digits));
      return false;
     }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
     {
      err = "PENDING_RETCODE=" + IntegerToString((int)res.retcode);
      Print("B100 pending RET ", err);
      return false;
     }
   ticket = res.order;
   Print("B100 pending ", EnumToString(typ), " ticket=", ticket,
         " @", DoubleToString(px, _Digits),
         " sl=", DoubleToString(slx, _Digits),
         " tp=", DoubleToString(tpx, _Digits));
   return true;
  }

#endif
