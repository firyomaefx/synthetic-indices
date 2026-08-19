#ifndef BREAK100_SAFEEV_MQH
#define BREAK100_SAFEEV_MQH

// After-cost SafeEV with mandatory NO_TRADE. No broker calls.

enum ENUM_B100_ACTION
  {
   B100_NO_TRADE    = 0,
   B100_ENTER_LONG  = 1,
   B100_ENTER_SHORT = 2
  };

struct B100Decision
  {
   ENUM_B100_ACTION  action;
   double            safe_ev;
   string            reason;
   ENUM_B100_ACTION  hypothetical;
   string            hypo_reason;
  };

struct B100Costs
  {
   double            spread;
   double            commission;
   double            slippage;
  };

double B100CostTotal(const B100Costs &c)
  {
   return c.spread + c.commission + c.slippage;
  }

string B100ActionName(const ENUM_B100_ACTION a)
  {
   if(a == B100_ENTER_LONG)
      return "ENTER_LONG";
   if(a == B100_ENTER_SHORT)
      return "ENTER_SHORT";
   return "NO_TRADE";
  }

void B100Decide(B100Decision &out,
                const int n_up,
                const int n_dn,
                const int n_bounce,
                const int n_censored,
                const B100Costs &costs,
                const double uncertainty_k,
                const int min_samples,
                const bool healthy,
                const bool order_intent)
  {
   out.action        = B100_NO_TRADE;
   out.safe_ev       = 0.0;
   out.reason        = "NO_CANDIDATES";
   out.hypothetical  = B100_NO_TRADE;
   out.hypo_reason   = "NO_CANDIDATES";

   if(!healthy)
     {
      out.reason      = "HEALTH_GATE_FAILED";
      out.hypo_reason = "HEALTH_GATE_FAILED";
      return;
     }

   const int n = n_up + n_dn + n_bounce + n_censored;
   const double uncertainty = (n < min_samples)
                              ? uncertainty_k * 4.0
                              : uncertainty_k / MathSqrt(MathMax(n, 1));

   const double p_up   = (n_up + 1.0) / (n + 2.0);
   const double p_dn   = (n_dn + 1.0) / (n + 2.0);
   const double p_fade = MathMax(0.0, 1.0 - p_up - p_dn);
   const double cost   = B100CostTotal(costs);

   const double ev_long  = p_up * 8.0 + p_dn * (-10.0) + p_fade * (-1.5) - cost;
   const double ev_short = p_dn * 8.0 + p_up * (-10.0) + p_fade * (-1.5) - cost;
   const double se_long  = ev_long  - uncertainty;
   const double se_short = ev_short - uncertainty;

   if(se_long <= 0.0 && se_short <= 0.0)
     {
      out.safe_ev     = MathMax(se_long, se_short);
      out.reason      = "NO_POSITIVE_SAFEEV";
      out.hypo_reason = "NO_POSITIVE_SAFEEV";
      return;
     }

   if(MathAbs(se_long - se_short) <= 1e-12)
     {
      out.safe_ev     = se_long;
      out.reason      = "AMBIGUOUS_ACTION";
      out.hypo_reason = "AMBIGUOUS_ACTION";
      return;
     }

   if(se_long > se_short)
     {
      out.hypothetical = B100_ENTER_LONG;
      out.safe_ev      = se_long;
      out.hypo_reason  = "POSITIVE_SAFEEV";
     }
   else
     {
      out.hypothetical = B100_ENTER_SHORT;
      out.safe_ev      = se_short;
      out.hypo_reason  = "POSITIVE_SAFEEV";
     }

   if(!order_intent)
     {
      out.action = B100_NO_TRADE;
      out.reason = "ORDER_INTENT_BLOCKED_OBSERVE";
      return;
     }

   out.action = out.hypothetical;
   out.reason = out.hypo_reason;
  }

#endif
