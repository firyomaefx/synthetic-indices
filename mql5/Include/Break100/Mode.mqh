#ifndef BREAK100_MODE_MQH
#define BREAK100_MODE_MQH

// Observe/Shadow never OrderSend. DEMO only on a verified demo account.
// LIVE is always rejected in source.

enum ENUM_B100_MODE
  {
   B100_OBSERVE = 0,
   B100_SHADOW  = 1,
   B100_DEMO    = 2,  // DEMO_AUTO — demo account only
   B100_LIVE    = 3,  // always rejected
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
  };

void B100ModeInit(B100Mode &m)
  {
   m.mode         = B100_OBSERVE;
   m.health       = B100_HEALTHY;
   m.block_reason = "";
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

string B100ApplyRequestedMode(B100Mode &m, const ENUM_B100_MODE requested)
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
   m.mode         = B100_OBSERVE;
   m.block_reason = "LIVE_DISABLED";
   return "LIVE_DISABLED: G5/G6 NO-GO — forced OBSERVE";
  }

void B100FailClosed(B100Mode &m, const string reason)
  {
   m.health       = B100_FAULT;
   m.block_reason = reason;
   if(m.mode == B100_DEMO)
      m.mode = B100_HALTED;
  }

void B100Halt(B100Mode &m, const string reason)
  {
   m.mode         = B100_HALTED;
   m.health       = B100_FAULT;
   m.block_reason = reason;
   Print("B100 HALTED ", reason);
  }

bool B100BrokerOrderIntentPermitted(const B100Mode &m)
  {
   if(m.health != B100_HEALTHY)
      return false;
   if(m.mode != B100_DEMO)
      return false;
   if(!B100IsDemoAccount())
      return false;
   return true;
  }

#endif
