#ifndef BREAK100_BOX_MQH
#define BREAK100_BOX_MQH

// Tight M30 pause: last 4–8 bars that stay in-zone, height ≤ 25% of last H4.
// Break = M30 close outside. SL/TP in box heights. No fade. No ATR decisions.

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
   int                  touches_hi;
   int                  touches_lo;
   double               close_loc;
   double               compress;
   double               h_vs_h4;
  };

void B100BoxInit(B100Box &b)
  {
   ZeroMemory(b);
   b.state = B100_BOX_SCAN;
  }

double B100H4Span(void)
  {
   const double hi = iHigh(_Symbol, PERIOD_H4, 1);
   const double lo = iLow(_Symbol, PERIOD_H4, 1);
   if(hi <= lo)
      return 0.0;
   return hi - lo;
  }

void B100RangePattern(const ENUM_TIMEFRAMES tf,
                      const int end_shift,
                      const int n_bars,
                      const double hi,
                      const double lo,
                      const double h4_span,
                      int &touches_hi,
                      int &touches_lo,
                      double &close_loc,
                      double &compress,
                      double &h_vs_h4)
  {
   touches_hi = 0;
   touches_lo = 0;
   close_loc = 0.5;
   compress = 1.0;
   h_vs_h4 = 0.0;
   const double H = hi - lo;
   if(H <= 0.0)
      return;
   h_vs_h4 = (h4_span > 0.0) ? (H / h4_span) : 0.0;
   const double band = 0.10 * H;
   const int last = end_shift + n_bars - 1;
   for(int i = end_shift; i <= last; i++)
     {
      if(iHigh(_Symbol, tf, i) >= hi - band)
         touches_hi++;
      if(iLow(_Symbol, tf, i) <= lo + band)
         touches_lo++;
     }
   const double c = iClose(_Symbol, tf, end_shift);
   close_loc = (c - lo) / H;
   if(n_bars >= 2)
     {
      const double h2 = MathMax(iHigh(_Symbol, tf, end_shift), iHigh(_Symbol, tf, end_shift + 1));
      const double l2 = MathMin(iLow(_Symbol, tf, end_shift), iLow(_Symbol, tf, end_shift + 1));
      compress = (h2 - l2) / H;
     }
  }

bool B100FindClusterAt(const ENUM_TIMEFRAMES tf,
                       const int end_shift,
                       const int min_bars,
                       const int max_bars,
                       const int atr_period,
                       const double h4_frac,
                       const double widen_frac,
                       double &hi,
                       double &lo,
                       datetime &t_left,
                       datetime &t_right,
                       int &n_bars,
                       double &atr)
  {
   if(end_shift < 1)
      return false;
   atr = 0.0;
   if(atr_period < 0)
      return false;
   const double h4_span = B100H4Span();
   if(h4_span <= 0.0)
      return false;
   const int minb = MathMax(4, min_bars);
   const int maxb = MathMax(minb, max_bars);
   if(iBars(_Symbol, tf) < end_shift + maxb + 2)
      return false;

   hi = iHigh(_Symbol, tf, end_shift);
   lo = iLow(_Symbol, tf, end_shift);
   n_bars = 1;
   for(int i = 1; i < minb; i++)
     {
      const double h = iHigh(_Symbol, tf, end_shift + i);
      const double l = iLow(_Symbol, tf, end_shift + i);
      if(h > hi) hi = h;
      if(l < lo) lo = l;
      n_bars++;
     }
   const double frac = MathMax(0.10, MathMin(h4_frac, 0.40));
   const double poke = MathMax(0.05, MathMin(widen_frac, 0.15));
   if(hi - lo > frac * h4_span)
      return false;
   for(int sh = end_shift + minb; sh <= end_shift + maxb - 1; sh++)
     {
      const double h = iHigh(_Symbol, tf, sh);
      const double l = iLow(_Symbol, tf, sh);
      const double H = hi - lo;
      if(H <= 0.0)
         break;
      const double room = poke * H;
      if(h > hi + room || l < lo - room)
         break;
      const double nhi = MathMax(hi, h);
      const double nlo = MathMin(lo, l);
      if(nhi - nlo > frac * h4_span)
         break;
      hi = nhi;
      lo = nlo;
      n_bars++;
     }
   if(n_bars < minb)
      return false;
   t_left = iTime(_Symbol, tf, end_shift + n_bars - 1);
   t_right = iTime(_Symbol, tf, end_shift);
   return true;
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
                        const double h4_frac,
                        const double widen_frac)
  {
   b.hist_n = 0;
   int shift = 2;
   const int last = MathMin(240, iBars(_Symbol, tf) - max_bars - 6);
   while(shift <= last && b.hist_n < B100_BOX_HIST)
     {
      double hi, lo, atr;
      datetime t0, t1;
      int n = 0;
      if(B100FindClusterAt(tf, shift, min_bars, max_bars, atr_period, h4_frac, widen_frac, hi, lo, t0, t1, n, atr))
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
                     const double h4_frac,
                     const double widen_frac,
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
      if(!new_bar)
         return "";
      const double c = iClose(_Symbol, tf, 1);
      const bool hit_buy  = (b.allow_buy && b.buy_stop > 0.0 && c >= b.buy_stop);
      const bool hit_sell = (b.allow_sell && b.sell_stop > 0.0 && c <= b.sell_stop);
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
         b.last_mfe   = c - b.buy_stop;
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
         b.last_mfe   = b.sell_stop - c;
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
   if(!B100FindClusterAt(tf, 1, min_bars, max_bars, atr_period, h4_frac, widen_frac, hi, lo, t0, t1, n, atr))
     {
      b.ready = false;
      return "";
     }
   if(t1 != 0 && t1 <= b.lock_bar)
     {
      b.ready = false;
      return "";
     }

   const double offset = MathMax(_Point, 0.02 * MathMax(hi - lo, _Point));
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
   B100RangePattern(tf, 1, n, hi, lo, B100H4Span(),
                    b.touches_hi, b.touches_lo, b.close_loc, b.compress, b.h_vs_h4);
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
      return "scanning for an M30 pause (3–8 overlapping bars inside H4)";
   if(b.dir_gate == "BUY")
      return "RL BUY-only  BUY STOP " + DoubleToString(b.buy_stop, _Digits);
   if(b.dir_gate == "SELL")
      return "RL SELL-only  SELL STOP " + DoubleToString(b.sell_stop, _Digits);
   return "RANGE " + IntegerToString(b.bars) + " bars  H " + DoubleToString(b.height, _Digits) +
          "  OCO BUY " + DoubleToString(b.buy_stop, _Digits) +
          "  SELL " + DoubleToString(b.sell_stop, _Digits);
  }

#endif
