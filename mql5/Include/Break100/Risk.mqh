#ifndef BREAK100_RISK_MQH
#define BREAK100_RISK_MQH

// Hard ceilings. Configured values cannot exceed these.

#define B100_MAX_CONCURRENT_POSITIONS 2
#define B100_HARD_RISK_FRACTION   0.0025
#define B100_HARD_LOSS_24H        0.01
#define B100_HARD_LOSS_WEEK       0.03
#define B100_HARD_DRAWDOWN        0.05

struct B100RiskSnap
  {
   double            loss_24h;
   double            loss_week;
   double            drawdown;
   int               open_for_symbol;
  };

string B100RiskGate(const B100RiskSnap &s)
  {
   if(s.loss_24h >= B100_HARD_LOSS_24H)
      return "ROLLING_24H_LOSS_STOP";
   if(s.loss_week >= B100_HARD_LOSS_WEEK)
      return "WEEKLY_LOSS_STOP";
   if(s.drawdown >= B100_HARD_DRAWDOWN)
      return "TOTAL_DRAWDOWN_STOP";
   // Two legs per setup (TP1 leg + runner) means two positions at once. This is
   // a concurrency ceiling, not a risk ceiling — the loss ceilings above and the
   // 0.25% fraction clamp below are untouched.
   if(s.open_for_symbol >= B100_MAX_CONCURRENT_POSITIONS)
      return "MAX_POSITION_REACHED";
   return "RISK_GATE_PASSED";
  }

double B100ClampRiskFraction(const double requested)
  {
   if(!MathIsValidNumber(requested) || requested <= 0.0)
      return B100_HARD_RISK_FRACTION;
   return MathMin(requested, B100_HARD_RISK_FRACTION);
  }

// Round volume down to broker step, never up.
double B100NormalizeLotsDown(double lots)
  {
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lots < vmin)
      return 0.0;
   lots = MathMin(lots, vmax);
   if(step <= 0.0)
      return vmin;
   const double steps = MathFloor((lots - vmin) / step + 1e-12);
   return vmin + steps * step;
  }

double B100StopRiskLots(const double equity,
                        const double risk_fraction,
                        const double entry,
                        const double stop)
  {
   const double frac = B100ClampRiskFraction(risk_fraction);
   const double dist = MathAbs(entry - stop);
   const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tval = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick <= 0.0 || tval <= 0.0 || dist <= 0.0 || equity <= 0.0)
      return 0.0;
   const double stop_ticks   = dist / tick;
   const double loss_per_lot = stop_ticks * tval;
   if(loss_per_lot <= 0.0)
      return 0.0;
   return B100NormalizeLotsDown((equity * frac) / loss_per_lot);
  }

#endif
