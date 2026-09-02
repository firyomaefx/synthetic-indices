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
   // Context captured when the box armed, so a closed row can be written even
   // though the box has moved on by then. Shadow.mqh is included before Box.mqh,
   // so these are primitives rather than a B100Box reference.
   datetime          armed_bar;
   double            height;
   double            spread_arm;
   string            exec_decision;   // why the real EA did or did not trade it
   int               touches_hi;
   int               touches_lo;
   double            close_loc;
   double            compress;
   double            h_vs_h4;
   int               imp_dir;
   string            phase;
  };

string B100ShadowKey(void)
  {
   string s = _Symbol;
   StringReplace(s, " ", "_");
   return s;
  }

// Realised P&L and trade count live only in memory, so every reattach or
// recompile silently restarted the ledger from zero. Persist them.
void B100ShadowStateSave(const B100ShadowBook &b)
  {
   const int fh = FileOpen("BREAK100_shadow_state_" + B100ShadowKey() + ".txt",
                           FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return;
   FileWriteString(fh, DoubleToString(b.realized, 2) + "\n" + IntegerToString(b.trades) + "\n");
   FileClose(fh);
  }

void B100ShadowStateLoad(B100ShadowBook &b)
  {
   const int fh = FileOpen("BREAK100_shadow_state_" + B100ShadowKey() + ".txt",
                           FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return;
   b.realized = StringToDouble(FileReadString(fh));
   b.trades   = (int)StringToInteger(FileReadString(fh));
   FileClose(fh);
  }

// Stamp the arm-time context onto the book. Called for EVERY armed box,
// including ones execution declines — that is what makes the ledger a
// counterfactual rather than a copy of the trade blotter.
void B100ShadowTag(B100ShadowBook &b,
                   const datetime armed_bar, const double height, const double spread_arm,
                   const int touches_hi, const int touches_lo, const double close_loc,
                   const double compress, const double h_vs_h4, const int imp_dir,
                   const string phase)
  {
   b.armed_bar   = armed_bar;
   b.height      = height;
   b.spread_arm  = spread_arm;
   b.touches_hi  = touches_hi;
   b.touches_lo  = touches_lo;
   b.close_loc   = close_loc;
   b.compress    = compress;
   b.h_vs_h4     = h_vs_h4;
   b.imp_dir     = imp_dir;
   b.phase       = phase;
  }

void B100ShadowSetDecision(B100ShadowBook &b, const string decision)
  {
   b.exec_decision = decision;
  }

// One row per closed virtual trade. Rows where exec_decision == "TRADED" are the
// filtered strategy; all rows together are the unfiltered one. Both read off the
// same ledger, so no second shadow book is needed.
void B100ShadowLedgerRow(const B100ShadowBook &b, const int dir, const double entry,
                         const double sl, const double tp, const double exit_px,
                         const string reason)
  {
   const string name = "BREAK100_shadow_v1_" + B100ShadowKey() + ".csv";
   const int fh = FileOpen(name, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI |
                           FILE_COMMON | FILE_SHARE_READ, ',');
   if(fh == INVALID_HANDLE)
      return;
   if(FileSize(fh) == 0)
      FileWrite(fh, "closed_utc", "armed_bar", "exec_decision", "dir", "entry", "sl", "tp",
                "exit_px", "reason", "r_multiple", "pnl_pts", "lots", "height", "spread_arm",
                "touches_hi", "touches_lo", "close_loc", "compress", "h_vs_h4", "imp_dir",
                "phase", "cum_realized", "trade_no");
   else
      FileSeek(fh, 0, SEEK_END);
   const double risk = MathAbs(entry - sl);
   const double r    = (risk > 0.0) ? ((exit_px - entry) * (double)dir / risk) : 0.0;
   const double pt   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double pts  = (pt > 0.0) ? ((exit_px - entry) * (double)dir / pt) : 0.0;
   FileWrite(fh,
             TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
             (long)b.armed_bar, b.exec_decision, dir, entry, sl, tp, exit_px, reason,
             DoubleToString(r, 4), DoubleToString(pts, 1), b.lots, b.height, b.spread_arm,
             b.touches_hi, b.touches_lo, b.close_loc, b.compress, b.h_vs_h4, b.imp_dir,
             b.phase, DoubleToString(b.realized, 2), b.trades);
   FileClose(fh);
  }

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
   // Write the row here, while dir/entry/sl/lots are still populated — the
   // clear below destroys them.
   B100ShadowLedgerRow(b, b.dir, b.entry, b.sl, b.tp, price, why);
   B100ShadowStateSave(b);
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
