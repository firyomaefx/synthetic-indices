#ifndef BREAK100_BOX_MQH
#define BREAK100_BOX_MQH

// Tight consolidation box (the red clusters): 3–8 overlapping M30 bars
// with range << ATR. Then virtual OCO: BUY STOP above, SELL STOP below.
// Closed bars only for detection. No broker pending orders.

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

struct B100Box
  {
   bool              ready;
   ENUM_B100_BOX_STATE state;
   double            high;
   double            low;
   double            height;
   double            buy_stop;
   double            sell_stop;
   datetime          t_left;
   datetime          t_right;
   int               bars;
   datetime          last_closed_bar;
   datetime          armed_bar;
   int               wait_bars;
   string            last_label;
   int               last_side;
   double            last_mfe;
   double            last_mae;
   double            last_hw;
   int               n_break_up;
   int               n_break_dn;
   int               n_fail;
   int               n_boxes;
   double            atr;
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
   const double a = h - l;
   const double b = MathAbs(h - pc);
   const double c = MathAbs(l - pc);
   return MathMax(a, MathMax(b, c));
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
                         const int start,   // oldest shift
                         const int end,     // newest shift (>=1)
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
   // Every bar must overlap the box (pause, not a staircase).
   const double overlap_need = 0.25 * rng;
   for(int i = end; i <= start; i++)
     {
      const double h = iHigh(_Symbol, tf, i);
      const double l = iLow(_Symbol, tf, i);
      const double ov = MathMin(h, hi) - MathMax(l, lo);
      if(ov < overlap_need)
         return false;
     }
   return true;
  }

bool B100FindCluster(const ENUM_TIMEFRAMES tf,
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
   atr = B100Atr(tf, atr_period, 1);
   const int minb = MathMax(3, min_bars);
   const int maxb = MathMax(minb, max_bars);
   if(iBars(_Symbol, tf) < maxb + atr_period + 3)
      return false;

   // Prefer the tightest qualifying cluster that ENDS at bar 1 (just closed).
   bool found = false;
   double best_rng = 1.0e100;
   for(int len = minb; len <= maxb; len++)
     {
      double h, l;
      const int start = len; // shift of oldest
      const int end   = 1;   // newest closed
      if(!B100WindowIsCluster(tf, start, end, atr, atr_max, h, l))
         continue;
      const double rng = h - l;
      if(rng < best_rng)
        {
         best_rng = rng;
         hi = h;
         lo = l;
         n_bars = len;
         t_left = iTime(_Symbol, tf, start);
         t_right = iTime(_Symbol, tf, end);
         found = true;
        }
     }
   return found;
  }

string B100BoxStep(B100Box &b,
                   const ENUM_TIMEFRAMES tf,
                   const int min_bars,
                   const int max_bars,
                   const int atr_period,
                   const double atr_max,
                   const int timeout_bars,
                   const double stop_offset)
  {
   const datetime closed = iTime(_Symbol, tf, 1);
   if(closed == 0)
      return "";
   if(closed == b.last_closed_bar)
      return "";
   const bool first = (b.last_closed_bar == 0);
   b.last_closed_bar = closed;
   if(first)
      return "";

   const double offset = MathMax(stop_offset, _Point);
   string labeled = "";

   if(b.state == B100_BOX_ARMED)
     {
      b.wait_bars++;
      const double h1 = iHigh(_Symbol, tf, 1);
      const double l1 = iLow(_Symbol, tf, 1);
      const double c1 = iClose(_Symbol, tf, 1);
      const bool hit_buy  = (h1 >= b.buy_stop);
      const bool hit_sell = (l1 <= b.sell_stop);

      if(hit_buy && hit_sell)
        {
         labeled = "CENSORED_OR_AMBIGUOUS";
         b.n_fail++;
         b.last_label = labeled;
         b.last_side  = 0;
         b.last_hw    = b.height;
         b.last_mfe   = 0.0;
         b.last_mae   = -b.height;
         b.state      = B100_BOX_SCAN;
         b.ready      = false;
         return labeled;
        }
      if(hit_buy)
        {
         labeled = "BREAKOUT_UP";
         b.n_break_up++;
         b.last_label = labeled;
         b.last_side  = 1;
         b.last_hw    = b.height;
         b.last_mfe   = MathMax(0.0, c1 - b.buy_stop);
         b.last_mae   = MathMin(0.0, l1 - b.buy_stop);
         b.state      = B100_BOX_SCAN;
         return labeled;
        }
      if(hit_sell)
        {
         labeled = "BREAKOUT_DOWN";
         b.n_break_dn++;
         b.last_label = labeled;
         b.last_side  = -1;
         b.last_hw    = b.height;
         b.last_mfe   = MathMax(0.0, b.sell_stop - c1);
         b.last_mae   = MathMin(0.0, b.sell_stop - h1);
         b.state      = B100_BOX_SCAN;
         return labeled;
        }
      if(b.wait_bars >= MathMax(2, timeout_bars))
        {
         labeled = "CENSORED_OR_AMBIGUOUS";
         b.n_fail++;
         b.last_label = labeled;
         b.last_side  = 0;
         b.last_hw    = b.height;
         b.state      = B100_BOX_SCAN;
         b.ready      = false;
         return labeled;
        }
      return "";
     }

   double hi, lo, atr;
   datetime t0, t1;
   int n = 0;
   if(!B100FindCluster(tf, min_bars, max_bars, atr_period, atr_max, hi, lo, t0, t1, n, atr))
     {
      b.ready = false;
      return "";
     }

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
   return "";
  }

string B100BoxWatchNote(const B100Box &b, const double mid)
  {
   if(b.state != B100_BOX_ARMED || !b.ready)
      return "scanning for a tight M30 pause (3–8 overlapping bars)";
   return "OCO armed  BUY STOP " + DoubleToString(b.buy_stop, _Digits) +
          "  SELL STOP " + DoubleToString(b.sell_stop, _Digits) +
          "  (no fade, no market order)";
  }

#endif
