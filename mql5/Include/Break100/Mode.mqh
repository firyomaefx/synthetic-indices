#ifndef BREAK100_MODE_MQH
#define BREAK100_MODE_MQH

// Broker-independent mode contract. Observe/Shadow never permit OrderSend.

enum ENUM_B100_MODE
  {
   B100_OBSERVE = 0,
   B100_SHADOW  = 1,
   B100_DEMO    = 2,  // rejected at init — G4 NO-GO
   B100_LIVE    = 3   // rejected at init — G5 NO-GO
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
      case B100_DEMO:    return "DEMO";
      case B100_LIVE:    return "LIVE";
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

// Source code never enables Demo/Live. Invalid requests fail closed to Observe.
string B100ApplyRequestedMode(B100Mode &m, const ENUM_B100_MODE requested)
  {
   B100ModeInit(m);
   if(requested == B100_OBSERVE)
      return "";
   if(requested == B100_SHADOW)
     {
      m.mode = B100_SHADOW;
      return "";
     }
   if(requested == B100_DEMO)
     {
      m.mode         = B100_OBSERVE;
      m.block_reason = "DEMO_GATE_MISSING";
      return "DEMO_GATE_MISSING: G4 evidence absent — forced OBSERVE";
     }
   m.mode         = B100_OBSERVE;
   m.block_reason = "LIVE_DISABLED";
   return "LIVE_DISABLED: G5/G6 NO-GO — forced OBSERVE";
  }

void B100FailClosed(B100Mode &m, const string reason)
  {
   m.mode         = B100_OBSERVE;
   m.health       = B100_FAULT;
   m.block_reason = reason;
  }

// Time-independent intent: never true in this EA (no execution adapter linked).
bool B100BrokerOrderIntentPermitted(const B100Mode &m)
  {
   return false;
  }

#endif
