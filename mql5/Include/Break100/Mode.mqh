#ifndef BREAK100_MODE_MQH
#define BREAK100_MODE_MQH

// Observe/Shadow never OrderSend. DEMO only on a verified demo account.
// LIVE requires four inputs to agree AND the chart button to be armed, and the
// arming is deliberately not persisted across restarts.

enum ENUM_B100_MODE
  {
   B100_OBSERVE = 0,
   B100_SHADOW  = 1,
   B100_DEMO    = 2,  // DEMO_AUTO — demo account only
   B100_LIVE    = 3,  // gated: input + real account + allowlist + armed button
   B100_OFF     = 4,
   B100_HALTED  = 5
  };

enum ENUM_B100_HEALTH
  {
   B100_HEALTHY = 0,
   B100_FAULT   = 1
  };

struct B100Mode
  {
   ENUM_B100_MODE    mode;
   ENUM_B100_HEALTH  health;
   string            block_reason;
   bool              live_armed;   // chart button; always false on (re)start
  };

void B100ModeInit(B100Mode &m)
  {
   m.mode         = B100_OBSERVE;
   m.health       = B100_HEALTHY;
   m.block_reason = "";
   m.live_armed   = false;
  }

string B100ModeName(const ENUM_B100_MODE mode)
  {
   switch(mode)
     {
      case B100_OBSERVE: return "OBSERVE";
      case B100_SHADOW:  return "SHADOW";
      case B100_DEMO:    return "DEMO_AUTO";
      case B100_LIVE:    return "LIVE";
      case B100_OFF:     return "OFF";
      case B100_HALTED:  return "HALTED";
     }
   return "UNKNOWN";
  }

bool B100IsDemoAccount(void)
  {
   const ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   return (trade_mode == ACCOUNT_TRADE_MODE_DEMO);
  }

bool B100IsRealAccount(void)
  {
   const ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   return (trade_mode == ACCOUNT_TRADE_MODE_REAL);
  }

string B100ApplyRequestedMode(B100Mode &m, const ENUM_B100_MODE requested,
                              const bool allow_live = false, const bool account_ok = false)
  {
   B100ModeInit(m);
   if(requested == B100_OFF)
     {
      m.mode = B100_OFF;
      return "OFF: no execution, capture may still run";
     }
   if(requested == B100_HALTED)
     {
      m.mode         = B100_HALTED;
      m.health       = B100_FAULT;
      m.block_reason = "HALTED";
      return "HALTED";
     }
   if(requested == B100_OBSERVE)
      return "";
   if(requested == B100_SHADOW)
     {
      m.mode = B100_SHADOW;
      return "";
     }
   if(requested == B100_DEMO)
     {
      if(!B100IsDemoAccount())
        {
         m.mode         = B100_OBSERVE;
         m.block_reason = "DEMO_ACCOUNT_REQUIRED";
         return "DEMO_ACCOUNT_REQUIRED: real/unknown account forced OBSERVE — no OrderSend";
        }
      m.mode = B100_DEMO;
      return "DEMO_AUTO: demo account only, SL required, Observe policy BOX_OCO_UCB";
     }
   // LIVE. Four independent conditions, all required, and even then no order is
   // sent until the operator arms the chart button. live_armed is never
   // persisted: every restart, recompile and reattach comes back disarmed.
   if(!allow_live)
     {
      m.mode         = B100_OBSERVE;
      m.block_reason = "LIVE_DISABLED_BY_INPUT";
      return "LIVE_DISABLED_BY_INPUT: set InpAllowLiveTrading to enable — forced OBSERVE";
     }
   if(!B100IsRealAccount())
     {
      m.mode         = B100_OBSERVE;
      m.block_reason = "LIVE_NEEDS_REAL_ACCOUNT";
      return "LIVE_NEEDS_REAL_ACCOUNT: this is not a real account — forced OBSERVE";
     }
   if(!account_ok)
     {
      m.mode         = B100_OBSERVE;
      m.block_reason = "LIVE_ACCOUNT_NOT_ALLOWLISTED";
      return "LIVE_ACCOUNT_NOT_ALLOWLISTED: InpLiveAccountLogin must equal this login — forced OBSERVE";
     }
   m.mode       = B100_LIVE;
   m.live_armed = false;
   return "LIVE permitted but DISARMED — press the chart button to arm. Orders are real.";
  }

void B100FailClosed(B100Mode &m, const string reason)
  {
   m.health       = B100_FAULT;
   m.block_reason = reason;
   // Any executing mode must halt, LIVE above all: a fault that left real
   // orders flowing is the one failure this system cannot walk back.
   if(m.mode == B100_DEMO || m.mode == B100_LIVE)
     {
      m.mode       = B100_HALTED;
      m.live_armed = false;
     }
  }

void B100Halt(B100Mode &m, const string reason)
  {
   m.mode         = B100_HALTED;
   m.health       = B100_FAULT;
   m.block_reason = reason;
   m.live_armed   = false;
   Print("B100 HALTED ", reason);
  }

// The single choke point every OrderSend passes through.
bool B100BrokerOrderIntentPermitted(const B100Mode &m)
  {
   if(m.health != B100_HEALTHY)
      return false;
   if(m.mode == B100_DEMO)
      return B100IsDemoAccount();
   if(m.mode == B100_LIVE)
      return m.live_armed && B100IsRealAccount();
   return false;
  }

// True when live orders are actually flowing — used for the chart warning.
bool B100LiveArmed(const B100Mode &m)
  {
   return m.mode == B100_LIVE && m.live_armed && B100IsRealAccount() && m.health == B100_HEALTHY;
  }

#endif
