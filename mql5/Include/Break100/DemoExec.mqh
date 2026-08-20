#ifndef BREAK100_DEMOEXEC_MQH
#define BREAK100_DEMOEXEC_MQH

// DEMO_AUTO adapter. OrderSend only after Mode permits AND demo account.
// This header must not be used to trade real accounts.

#define B100_MAGIC 100165

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

bool B100DemoSend(const int dir,
                  const double sl,
                  const double tp,
                  const double lots,
                  const string signal_id,
                  string &err)
  {
   err = "";
   if(!B100IsDemoAccount())
     {
      err = "DEMO_ACCOUNT_REQUIRED";
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

#endif
