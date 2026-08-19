#ifndef BREAK100_CHANNEL_MQH
#define BREAK100_CHANNEL_MQH

// Causal Kalman centre + MAD half-width. No broker calls.

struct B100Pending
  {
   bool              active;
   int               side;           // +1 up, -1 down
   int               start_seq;
   double            centre;
   double            half_width;
   double            touch_price;
   double            extreme;
   double            mfe;
   double            mae;
   int               ticks_outside;
  };

struct B100Pipe
  {
   double            kalman_x;
   double            kalman_p;
   double            residuals[];
   int               res_count;
   int               mad_window;
   double            kalman_q;
   double            kalman_r_floor;
   double            mad_k;
   int               persist_ticks;
   int               label_horizon;
   double            last_mid;
   int               last_sign;
   int               run;
   B100Pending       pending;
   int               seq;
   int               touch_count;
   int               n_break_up;
   int               n_break_dn;
   int               n_bounce;
   int               n_censored;
   double            half_width;
   double            residual;
   bool              warmed;
   string            last_label;
   int               last_label_side;
   double            last_mfe;
   double            last_mae;
   double            last_hw;
  };

void B100PipeInit(B100Pipe &p,
                  const double first_mid,
                  const int mad_window,
                  const double kalman_q,
                  const double kalman_r_floor,
                  const double mad_k,
                  const int persist_ticks,
                  const int label_horizon)
  {
   p.kalman_x        = first_mid;
   p.kalman_p        = 1.0;
   p.res_count       = 0;
   p.mad_window      = MathMax(20, mad_window);
   p.kalman_q        = kalman_q;
   p.kalman_r_floor  = kalman_r_floor;
   p.mad_k           = mad_k;
   p.persist_ticks   = persist_ticks;
   p.label_horizon   = label_horizon;
   p.last_mid        = first_mid;
   p.last_sign       = 0;
   p.run             = 0;
   p.pending.active  = false;
   p.seq             = 0;
   p.touch_count     = 0;
   p.n_break_up      = 0;
   p.n_break_dn      = 0;
   p.n_bounce        = 0;
   p.n_censored      = 0;
   p.half_width      = 0.0;
   p.residual        = 0.0;
   p.warmed          = false;
   p.last_label      = "";
   p.last_label_side = 0;
   p.last_mfe        = 0.0;
   p.last_mae        = 0.0;
   p.last_hw         = 0.0;
   ArrayResize(p.residuals, p.mad_window);
   ArrayInitialize(p.residuals, 0.0);
  }

double B100MedianAbs(const double &src[], const int n)
  {
   if(n <= 0)
      return 0.0;
   double tmp[];
   ArrayResize(tmp, n);
   for(int i = 0; i < n; i++)
      tmp[i] = src[i];
   ArraySort(tmp);
   const int mid = n / 2;
   const double med = (n % 2 != 0) ? tmp[mid] : 0.5 * (tmp[mid - 1] + tmp[mid]);
   for(int i = 0; i < n; i++)
      tmp[i] = MathAbs(src[i] - med);
   ArraySort(tmp);
   return (n % 2 != 0) ? tmp[mid] : 0.5 * (tmp[mid - 1] + tmp[mid]);
  }

void B100PushResidual(B100Pipe &p, const double r)
  {
   if(p.res_count < p.mad_window)
     {
      p.residuals[p.res_count++] = r;
      return;
     }
   for(int i = 1; i < p.mad_window; i++)
      p.residuals[i - 1] = p.residuals[i];
   p.residuals[p.mad_window - 1] = r;
  }

// Returns label string when an event closes, otherwise empty.
string B100Ingest(B100Pipe &p, const double bid, const double ask)
  {
   const double mid    = 0.5 * (bid + ask);
   const double spread = MathMax(ask - bid, 0.0);
   const double R      = MathMax(p.kalman_r_floor, spread * spread);

   p.kalman_p += p.kalman_q;
   const double K = p.kalman_p / (p.kalman_p + R);
   p.kalman_x += K * (mid - p.kalman_x);
   p.kalman_p *= (1.0 - K);

   p.residual = mid - p.kalman_x;
   B100PushResidual(p, p.residual);

   const double scale = 1.4826 * B100MedianAbs(p.residuals, p.res_count);
   p.half_width = MathMax(p.mad_k * MathMax(scale, spread), 2.0 * spread);
   p.half_width = MathMax(p.half_width, spread);

   const int sign = (p.residual == 0.0) ? 0 : (p.residual > 0.0 ? 1 : -1);
   if(sign != 0 && sign == p.last_sign)
      p.run++;
   else
      p.run = (sign == 0) ? 0 : 1;
   if(sign != 0)
      p.last_sign = sign;

   p.last_mid = mid;
   p.seq++;
   p.warmed = (p.res_count > 12);

   const double channel_width  = 2.0 * p.half_width;
   const double touch_distance = MathMax(2.0 * spread, 0.05 * channel_width);
   const bool   outside        = MathAbs(p.residual) >= (p.half_width - touch_distance);
   const bool   far_outside    = MathAbs(p.residual) >= p.half_width;
   const bool   near_centre    = MathAbs(p.residual) <= 0.22 * p.half_width;

   string labeled = "";

   if(p.pending.active)
     {
      B100Pending pend = p.pending;
      const double excursion = (mid - pend.touch_price) * (double)pend.side;
      pend.mfe = MathMax(pend.mfe, excursion);
      pend.mae = MathMin(pend.mae, excursion);
      if(pend.side > 0)
         pend.extreme = MathMax(pend.extreme, mid);
      else
         pend.extreme = MathMin(pend.extreme, mid);
      if(far_outside && ((pend.side > 0 && p.residual > 0.0) || (pend.side < 0 && p.residual < 0.0)))
         pend.ticks_outside++;

      const bool horizon = (p.seq - pend.start_seq) >= p.label_horizon;
      const bool flipped = (pend.side > 0 && p.residual < -0.6 * p.half_width) ||
                           (pend.side < 0 && p.residual >  0.6 * p.half_width);

      if(pend.ticks_outside >= p.persist_ticks && far_outside)
         labeled = (pend.side > 0) ? "BREAKOUT_UP" : "BREAKOUT_DOWN";
      else if(near_centre && (p.seq - pend.start_seq) >= 3)
         labeled = "BOUNCE";
      else if(flipped || horizon)
         labeled = "CENSORED_OR_AMBIGUOUS";

      if(labeled != "")
        {
         if(labeled == "BREAKOUT_UP")
            p.n_break_up++;
         else if(labeled == "BREAKOUT_DOWN")
            p.n_break_dn++;
         else if(labeled == "BOUNCE")
            p.n_bounce++;
         else
            p.n_censored++;
         p.last_label      = labeled;
         p.last_label_side = pend.side;
         p.last_mfe        = pend.mfe;
         p.last_mae        = pend.mae;
         p.last_hw         = pend.half_width;
         pend.active       = false;
        }
      p.pending = pend;
     }
   else if(outside && p.warmed)
     {
      p.touch_count++;
      p.pending.active        = true;
      p.pending.side          = (p.residual > 0.0) ? 1 : -1;
      p.pending.start_seq     = p.seq;
      p.pending.centre        = p.kalman_x;
      p.pending.half_width    = p.half_width;
      p.pending.touch_price   = mid;
      p.pending.extreme       = mid;
      p.pending.mfe           = 0.0;
      p.pending.mae           = 0.0;
      p.pending.ticks_outside = far_outside ? 1 : 0;
     }

   return labeled;
  }

#endif
