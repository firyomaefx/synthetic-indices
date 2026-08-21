#ifndef BREAK100_SHADOW_MQH
#define BREAK100_SHADOW_MQH

// Virtual ledger + virtual OCO stops. Never include Trade.mqh.

struct B100ShadowBook
  {
   bool              open;
   int               dir;
   double            entry;
   double            sl;
   double            tp;
   double            lots;
   double            realized;
   int               trades;
   datetime          opened_at;
   bool              pend_buy;
   bool              pend_sell;
   double            buy_px;
   double            sell_px;
   double            sl_buy;
   double            sl_sell;
   double            tp_buy;
   double            tp_sell;
   string            last_event;
   double            last_pnl_pts;
  };

void B100ShadowInit(B100ShadowBook &b)
  {
   ZeroMemory(b);
   b.last_event = "";
  }

void B100ShadowCancelOco(B100ShadowBook &b)
  {
   if(b.pend_buy || b.pend_sell)
      b.last_event = "OCO_CANCEL";
   b.pend_buy  = false;
   b.pend_sell = false;
  }

void B100ShadowArmOco(B100ShadowBook &b,
                      const double buy_px,
                      const double sell_px,
                      const double sl_buy,
                      const double sl_sell,
                      const double tp_buy,
                      const double tp_sell,
                      const double lots)
  {
   if(b.open || lots <= 0.0)
      return;
   b.pend_buy   = (buy_px > 0.0);
   b.pend_sell  = (sell_px > 0.0);
   b.buy_px     = buy_px;
   b.sell_px    = sell_px;
   b.sl_buy     = sl_buy;
   b.sl_sell    = sl_sell;
   b.tp_buy     = tp_buy;
   b.tp_sell    = tp_sell;
   b.lots       = lots;
   b.last_event = "OCO_ARM";
  }

void B100ShadowOpen(B100ShadowBook &b,
                    const int dir,
                    const double entry,
                    const double sl,
                    const double lots)
  {
   if(b.open || lots <= 0.0)
      return;
   b.open       = true;
   b.dir        = dir;
   b.entry      = entry;
   b.sl         = sl;
   b.lots       = lots;
   b.opened_at  = TimeCurrent();
   b.trades++;
   B100ShadowCancelOco(b);
   b.last_event = (dir > 0) ? "FILL_BUY" : "FILL_SELL";
  }

void B100ShadowClose(B100ShadowBook &b, const double price, const string why)
  {
   if(!b.open)
      return;
   const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tval = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick > 0.0 && tval > 0.0)
     {
      const double ticks = (price - b.entry) / tick * (double)b.dir;
      b.realized += ticks * tval * b.lots;
     }
   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   b.last_pnl_pts = (pt > 0.0) ? ((price - b.entry) / pt * (double)b.dir) : 0.0;
   b.last_event = why;
   b.open  = false;
   b.dir   = 0;
   b.lots  = 0.0;
  }

void B100ShadowMark(B100ShadowBook &b, const double bid, const double ask)
  {
   b.last_event = "";
   if(!b.open)
     {
      if(b.pend_buy && b.pend_sell && ask >= b.buy_px && bid <= b.sell_px)
        {
         B100ShadowCancelOco(b);
         return;
        }
      if(b.pend_buy && ask >= b.buy_px)
        {
         b.tp = b.tp_buy;
         B100ShadowOpen(b, 1, b.buy_px, b.sl_buy, b.lots);
         return;
        }
      if(b.pend_sell && bid <= b.sell_px)
        {
         b.tp = b.tp_sell;
         B100ShadowOpen(b, -1, b.sell_px, b.sl_sell, b.lots);
         return;
        }
      return;
     }
   const double px = (b.dir > 0) ? bid : ask;
   if(b.dir > 0 && px <= b.sl)
      B100ShadowClose(b, px, "CLOSE_SL");
   else if(b.dir < 0 && px >= b.sl)
      B100ShadowClose(b, px, "CLOSE_SL");
   else if(b.tp > 0.0)
     {
      if(b.dir > 0 && px >= b.tp)
         B100ShadowClose(b, px, "CLOSE_TP");
      else if(b.dir < 0 && px <= b.tp)
         B100ShadowClose(b, px, "CLOSE_TP");
     }
  }

#endif
