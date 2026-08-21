#ifndef BREAK100_BOX_MQH
#define BREAK100_BOX_MQH

// Tight pause (3–8 overlapping M30 bars, range <= k*ATR).
// OCO: BUY STOP above, SELL STOP below. Shadow simulates; DEMO_AUTO places both.

enum ENUM_B100_STRAT
  {
   B100_STRAT_CHANNEL = 0,
   B100_STRAT_BOX_M30 = 1
  };

enum ENUM_B100_BOX_STATE
  {
   B100_BOX_SCAN  = 0,
   B100_BOX_ARMED = 1
  };

#define B100_BOX_HIST 24

struct B100BoxHist
  {
   datetime t_left;
   datetime t_right;
   double   high;
   double   low;
  };

struct B100Box
  {
   bool                 ready;
   ENUM_B100_BOX_STATE  state;
   double               high;
   double               low;
   double               height;
   double               buy_stop;
   double               sell_stop;
   datetime             t_left;
   datetime             t_right;
   int                  bars;
   datetime             last_closed_bar;
   datetime             armed_bar;
   int                  wait_bars;
   string               last_label;
   int                  last_side;
   double               last_mfe;
   double               last_mae;
   double               last_hw;
   int                  n_break_up;
   int                  n_break_dn;
   int                  n_fail;
   int                  n_boxes;
   double               atr;
   B100BoxHist          hist[B100_BOX_HIST];
   int                  hist_n;
   bool                 just_armed;
   datetime             lock_bar;
   bool                 allow_buy;
   bool                 allow_sell;
   string               dir_gate;
  };

void B100BoxInit(B100Box &b)
  {
   ZeroMemory(b);
   b.state = B100_BOX_SCAN;
  }

double B100TrueRange(const ENUM_TIMEFRAMES tf, const int shift)
  {
   const double h = iHigh(_Symbol, tf, shift);
   const double l = iLow(_Symbol, tf, shift);
   const double pc = iClose(_Symbol, tf, shift + 1);
   return MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
  }

double B100Atr(const ENUM_TIMEFRAMES tf, const int period, const int shift)
  {
   const int n = MathMax(4, period);
   double s = 0.0;
   for(int i = 0; i < n; i++)
      s += B100TrueRange(tf, shift + i);
   return s / n;
  }

bool B100WindowIsCluster(const ENUM_TIMEFRAMES tf,
                         const int start,
                         const int end,
                         const double atr,
                         const double atr_max,
                         double &hi,
                         double &lo)
  {
   if(end < 1 || start < end)
      return false;
   hi = iHigh(_Symbol, tf, end);
   lo = iLow(_Symbol, tf, end);
   for(int i = end; i <= start; i++)
     {
      const double h = iHigh(_Symbol, tf, i);
      const double l = iLow(_Symbol, tf, i);
      if(h > hi) hi = h;
      if(l < lo) lo = l;
     }
   const double rng = hi - lo;
   if(rng <= 0.0 || atr <= 0.0)
      return false;
   if(rng > atr_max * atr)
      return false;
   const double overlap_need = 0.10 * rng;
   for(int i = end; i <= start; i++)
     {
      const double h = iHigh(_Symbol, tf, i);
      const double l = iLow(_Symbol, tf, i);
      if(MathMin(h, hi) - MathMax(l, lo) < overlap_need)
         return false;
     }
   return true;
  }

bool B100FindClusterAt(const ENUM_TIMEFRAMES tf,
                       const int end_shift,
                       const int min_bars,
                       const int max_bars,
                       const int atr_period,
                       const double atr_max,
                       double &hi,
                       double &lo,
                       datetime &t_left,
                       datetime &t_right,
                       int &n_bars,
                       double &atr)
  {
   if(end_shift < 1)
      return false;
   atr = B100Atr(tf, atr_period, end_shift);
   const int minb = MathMax(3, min_bars);
   const int maxb = MathMax(minb, max_bars);
   if(iBars(_Symbol, tf) < end_shift + maxb + atr_period + 2)
      return false;

   bool found = false;
   double best_rng = 1.0e100;
   for(int len = minb; len <= maxb; len++)
     {
      double h, l;
      const int start = end_shift + len - 1;
      if(!B100WindowIsCluster(tf, start, end_shift, atr, atr_max, h, l))
         continue;
      const double rng = h - l;
      if(rng < best_rng)
        {
         best_rng = rng;
         hi = h;
         lo = l;
         n_bars = len;
         t_left = iTime(_Symbol, tf, start);
         t_right = iTime(_Symbol, tf, end_shift);
         found = true;
        }
     }
   return found;
  }

void B100BoxPushHist(B100Box &b, const datetime t0, const datetime t1, const double hi, const double lo)
  {
   if(b.hist_n < B100_BOX_HIST)
     {
      b.hist[b.hist_n].t_left  = t0;
      b.hist[b.hist_n].t_right = t1;
      b.hist[b.hist_n].high    = hi;
      b.hist[b.hist_n].low     = lo;
      b.hist_n++;
      return;
     }
   for(int i = 1; i < B100_BOX_HIST; i++)
      b.hist[i - 1] = b.hist[i];
   b.hist[B100_BOX_HIST - 1].t_left  = t0;
   b.hist[B100_BOX_HIST - 1].t_right = t1;
   b.hist[B100_BOX_HIST - 1].high    = hi;
   b.hist[B100_BOX_HIST - 1].low     = lo;
  }

void B100BoxScanHistory(B100Box &b,
                        const ENUM_TIMEFRAMES tf,
                        const int min_bars,
                        const int max_bars,
                        const int atr_period,
                        const double atr_max)
  {
   b.hist_n = 0;
   int shift = 2;
   const int last = MathMin(180, iBars(_Symbol, tf) - max_bars - atr_period - 4);
   while(shift <= last && b.hist_n < B100_BOX_HIST)
     {
      double hi, lo, atr;
      datetime t0, t1;
      int n = 0;
      if(B100FindClusterAt(tf, shift, min_bars, max_bars, atr_period, atr_max, hi, lo, t0, t1, n, atr))
        {
         B100BoxPushHist(b, t0, t1, hi, lo);
         shift += n;
        }
      else
         shift++;
     }
  }

string B100BoxOnTick(B100Box &b,
                     const ENUM_TIMEFRAMES tf,
                     const int min_bars,
                     const int max_bars,
                     const int atr_period,
                     const double atr_max,
                     const int timeout_bars,
                     const double bid,
                     const double ask)
  {
   const datetime closed = iTime(_Symbol, tf, 1);
   const bool new_bar = (closed != 0 && closed != b.last_closed_bar);
   if(new_bar)
     {
      if(b.last_closed_bar != 0 && b.state == B100_BOX_ARMED)
         b.wait_bars++;
      b.last_closed_bar = closed;
     }

   if(b.state == B100_BOX_ARMED)
     {
      const bool hit_buy  = (b.allow_buy && b.buy_stop > 0.0 && ask >= b.buy_stop);
      const bool hit_sell = (b.allow_sell && b.sell_stop > 0.0 && bid <= b.sell_stop);
      if(hit_buy && hit_sell)
        {
         b.last_label = "CENSORED_OR_AMBIGUOUS";
         b.last_side  = 0;
         b.last_hw    = b.height;
         b.last_mfe   = 0.0;
         b.last_mae   = -b.height;
         b.n_fail++;
         b.lock_bar = closed;
         b.state = B100_BOX_SCAN;
         b.ready = false;
         return b.last_label;
        }
      if(hit_buy)
        {
         b.last_label = "BREAKOUT_UP";
         b.last_side  = 1;
         b.last_hw    = b.height;
         b.last_mfe   = ask - b.buy_stop;
         b.last_mae   = 0.0;
         b.n_break_up++;
         b.lock_bar = closed;
         b.state = B100_BOX_SCAN;
         return b.last_label;
        }
      if(hit_sell)
        {
         b.last_label = "BREAKOUT_DOWN";
         b.last_side  = -1;
         b.last_hw    = b.height;
         b.last_mfe   = b.sell_stop - bid;
         b.last_mae   = 0.0;
         b.n_break_dn++;
         b.lock_bar = closed;
         b.state = B100_BOX_SCAN;
         return b.last_label;
        }
      if(b.wait_bars >= MathMax(2, timeout_bars))
        {
         b.last_label = "CENSORED_OR_AMBIGUOUS";
         b.last_side  = 0;
         b.last_hw    = b.height;
         b.n_fail++;
         b.lock_bar = closed;
         b.state = B100_BOX_SCAN;
         b.ready = false;
         return b.last_label;
        }
      return "";
     }

   if(closed != 0 && b.lock_bar != 0 && closed <= b.lock_bar)
     {
      b.ready = false;
      return "";
     }

   double hi, lo, atr;
   datetime t0, t1;
   int n = 0;
   if(!B100FindClusterAt(tf, 1, min_bars, max_bars, atr_period, atr_max, hi, lo, t0, t1, n, atr))
     {
      b.ready = false;
      return "";
     }
   if(t1 != 0 && t1 <= b.lock_bar)
     {
      b.ready = false;
      return "";
     }

   const double offset = MathMax(_Point, 0.02 * MathMax(atr, _Point));
   b.ready     = true;
   b.state     = B100_BOX_ARMED;
   b.high      = hi;
   b.low       = lo;
   b.height    = hi - lo;
   b.t_left    = t0;
   b.t_right   = t1;
   b.bars      = n;
   b.atr       = atr;
   b.buy_stop  = hi + offset;
   b.sell_stop = lo - offset;
   b.armed_bar = closed;
   b.wait_bars = 0;
   b.n_boxes++;
   b.just_armed = true;
   b.allow_buy  = true;
   b.allow_sell = true;
   b.dir_gate   = "BOTH";
   B100BoxPushHist(b, t0, t1, hi, lo);
   return "";
  }

void B100BoxApplyDirGate(B100Box &b, const string gate)
  {
   b.dir_gate = gate;
   if(gate == "SKIP")
     {
      b.state = B100_BOX_SCAN;
      b.ready = false;
      b.just_armed = false;
      b.allow_buy = false;
      b.allow_sell = false;
      return;
     }
   if(gate == "BUY")
     {
      b.allow_buy  = true;
      b.allow_sell = false;
      b.sell_stop  = 0.0;
     }
   else if(gate == "SELL")
     {
      b.allow_buy  = false;
      b.allow_sell = true;
      b.buy_stop   = 0.0;
     }
  }

string B100BoxWatchNote(const B100Box &b, const double mid)
  {
   if(b.state != B100_BOX_ARMED || !b.ready)
      return "scanning for a tight M30 pause (3–8 overlapping bars)";
   if(b.dir_gate == "BUY")
      return "RL BUY-only  BUY STOP " + DoubleToString(b.buy_stop, _Digits);
   if(b.dir_gate == "SELL")
      return "RL SELL-only  SELL STOP " + DoubleToString(b.sell_stop, _Digits);
   return "OCO  BUY STOP " + DoubleToString(b.buy_stop, _Digits) +
          "  SELL STOP " + DoubleToString(b.sell_stop, _Digits) +
          "  first fill deletes the other";
  }

#endif
