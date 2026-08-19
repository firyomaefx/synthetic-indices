#ifndef BREAK100_SHADOW_MQH
#define BREAK100_SHADOW_MQH

// Virtual ledger only. This file must never include <Trade/Trade.mqh>.

struct B100ShadowBook
  {
   bool              open;
   int               dir;          // +1 long, -1 short
   double            entry;
   double            sl;
   double            lots;
   double            realized;
   int               trades;
   datetime          opened_at;
  };

void B100ShadowInit(B100ShadowBook &b)
  {
   b.open       = false;
   b.dir        = 0;
   b.entry      = 0.0;
   b.sl         = 0.0;
   b.lots       = 0.0;
   b.realized   = 0.0;
   b.trades     = 0;
   b.opened_at  = 0;
  }

void B100ShadowOpen(B100ShadowBook &b,
                    const int dir,
                    const double entry,
                    const double sl,
                    const double lots)
  {
   if(b.open || lots <= 0.0)
      return;
   b.open      = true;
   b.dir       = dir;
   b.entry     = entry;
   b.sl        = sl;
   b.lots      = lots;
   b.opened_at = TimeCurrent();
   b.trades++;
  }

void B100ShadowClose(B100ShadowBook &b, const double price)
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
   b.open  = false;
   b.dir   = 0;
   b.lots  = 0.0;
  }

void B100ShadowMark(B100ShadowBook &b, const double bid, const double ask)
  {
   if(!b.open)
      return;
   const double px = (b.dir > 0) ? bid : ask;
   if(b.dir > 0 && px <= b.sl)
      B100ShadowClose(b, px);
   else if(b.dir < 0 && px >= b.sl)
      B100ShadowClose(b, px);
  }

#endif
