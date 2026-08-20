#ifndef BREAK100_BOX_MQH
#define BREAK100_BOX_MQH

// Causal M30 (or Inp TF) Donchian box. Closed bars only. No broker calls.
// Hypothesis: after a persisted close outside the box, fade is disabled.

enum ENUM_B100_STRAT
  {
   B100_STRAT_CHANNEL = 0,   // tick Kalman + MAD
   B100_STRAT_BOX_M30 = 1    // M30 support/resistance box, breakout only
  };

struct B100Box
  {
   bool              ready;
   double            high;
   double            low;
   double            height;
   datetime          t_left;
   datetime          t_right;
   int               persist_up;
   int               persist_dn;
   datetime          last_closed_bar;
   string            last_label;
   int               last_side;
   double            last_mfe;
   double            last_mae;
   double            last_hw;
   int               n_break_up;
   int               n_break_dn;
   int               n_fail;
   datetime          signaled_bar;
  };

void B100BoxInit(B100Box &b)
  {
   ZeroMemory(b);
  }

void B100BoxRebuild(B100Box &b, const ENUM_TIMEFRAMES tf, const int bars)
  {
   const int n = MathMax(4, bars);
   if(iBars(_Symbol, tf) < n + 3)
     {
      b.ready = false;
      return;
     }
   // Prior closed bars only: 2 .. n+1. Bar 1 is the candidate (just closed).
   double hi = iHigh(_Symbol, tf, 2);
   double lo = iLow(_Symbol, tf, 2);
   datetime left = iTime(_Symbol, tf, n + 1);
   for(int i = 3; i <= n + 1; i++)
     {
      const double h = iHigh(_Symbol, tf, i);
      const double l = iLow(_Symbol, tf, i);
      if(h > hi) hi = h;
      if(l < lo) lo = l;
     }
   b.high    = hi;
   b.low     = lo;
   b.height  = hi - lo;
   b.t_left  = left;
   b.t_right = iTime(_Symbol, tf, 2);
   b.ready   = (b.height > 0.0);
  }

// Returns a label only on a newly closed TF bar. Never uses bar 0 (forming).
string B100BoxStep(B100Box &b,
                   const ENUM_TIMEFRAMES tf,
                   const int bars,
                   const int persist_need)
  {
   const datetime closed = iTime(_Symbol, tf, 1);
   if(closed == 0)
      return "";
   if(closed == b.last_closed_bar)
      return "";
   const bool first = (b.last_closed_bar == 0);
   b.last_closed_bar = closed;

   B100BoxRebuild(b, tf, bars);
   if(!b.ready || first)
      return "";

   const double c = iClose(_Symbol, tf, 1);
   const int need = MathMax(1, persist_need);
   string labeled = "";

   if(c > b.high)
     {
      b.persist_up++;
      b.persist_dn = 0;
     }
   else if(c < b.low)
     {
      b.persist_dn++;
      b.persist_up = 0;
     }
   else
     {
      if(b.persist_up >= need || b.persist_dn >= need)
        {
         labeled = "CENSORED_OR_AMBIGUOUS";
         b.n_fail++;
         b.last_label = labeled;
         b.last_side  = 0;
         b.last_hw    = b.height;
         b.last_mfe   = 0.0;
         b.last_mae   = -0.5 * b.height;
        }
      b.persist_up = 0;
      b.persist_dn = 0;
      return labeled;
     }

   if(b.persist_up >= need && b.signaled_bar != closed)
     {
      labeled = "BREAKOUT_UP";
      b.n_break_up++;
      b.last_label = labeled;
      b.last_side  = 1;
      b.last_hw    = b.height;
      b.last_mfe   = c - b.high;
      b.last_mae   = 0.0;
      b.signaled_bar = closed;
     }
   else if(b.persist_dn >= need && b.signaled_bar != closed)
     {
      labeled = "BREAKOUT_DOWN";
      b.n_break_dn++;
      b.last_label = labeled;
      b.last_side  = -1;
      b.last_hw    = b.height;
      b.last_mfe   = b.low - c;
      b.last_mae   = 0.0;
      b.signaled_bar = closed;
     }
   return labeled;
  }

string B100BoxWatchNote(const B100Box &b, const double mid)
  {
   if(!b.ready)
      return "M30 box warming — need closed bars";
   const double near = 0.12 * b.height;
   if(mid >= b.high - near)
      return "at box resistance — waiting M30 close ABOVE (no fade)";
   if(mid <= b.low + near)
      return "at box support — waiting M30 close BELOW (no fade)";
   return "inside M30 box — no bounce entry on this strategy";
  }

#endif
