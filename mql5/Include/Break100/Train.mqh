#ifndef BREAK100_TRAIN_MQH
#define BREAK100_TRAIN_MQH

// Quality-gated episode log for ML/RL. One row after the path is known.
// Does not replace ticks/setup/outcome warehouse. No broker orders.

struct B100Episode
  {
   bool     active;
   bool     tracking;
   int      quality;
   string   q_reason;
   int      side;
   string   label;
   string   exit_why;
   datetime armed_utc;
   datetime fill_utc;
   datetime armed_bar;
   int      bars_box;
   double   height;
   double   atr;
   double   spread_arm;
   double   buy_stop;
   double   sell_stop;
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   double   tp3;
   double   hw;
   double   mfe;
   double   mae;
   int      hit_tp1;
   int      hit_tp2;
   int      hit_tp3;
   int      hit_sl;
   int      bars_held;
   datetime last_bar;
   int      hour_gmt;
   int      dow;
   double   m1_rng;
   double   m5_rng;
   double   m30_rng;
   double   h4_dist;
   int      arm;
   ulong    id;
   int      touches_hi;
   int      touches_lo;
   double   close_loc;
   double   compress;
   double   h_vs_h4;
   int      imp_dir;
   double   imp_h;
   double   imp_vs_box;
   double   box_at;
   string   phase;
  };

void B100TrainInit(B100Episode &e)
  {
   ZeroMemory(e);
  }

int B100TrainFile(void)
  {
   string s = _Symbol;
   StringReplace(s, " ", "_");
   return FileOpen("BREAK100_train_" + s + ".csv",
                   FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, ',');
  }

void B100TrainEnsureHeader(const int fh)
  {
   if(fh == INVALID_HANDLE)
      return;
   if(FileSize(fh) == 0)
      FileWrite(fh,
                "side", "label", "mfe", "mae", "hw", "arm", "quality", "exit",
                "mfe_r", "mae_r", "height", "atr", "spread", "bars_box",
                "hour", "dow", "hit_tp1", "hit_tp2", "hit_tp3", "hit_sl",
                "bars_held", "weight", "episode_id", "q_reason",
                "buy_stop", "sell_stop", "entry", "sl", "tp1", "tp2", "tp3",
                "touches_hi", "touches_lo", "close_loc", "compress", "h_vs_h4",
                "imp_dir", "imp_h", "imp_vs_box", "box_at", "phase");
   else
      FileSeek(fh, 0, SEEK_END);
  }

double B100TfRange(const ENUM_TIMEFRAMES tf)
  {
   MqlRates r[];
   if(CopyRates(_Symbol, tf, 1, 1, r) < 1)
      return 0.0;
   return r[0].high - r[0].low;
  }

double B100TfClose(const ENUM_TIMEFRAMES tf)
  {
   MqlRates r[];
   if(CopyRates(_Symbol, tf, 1, 1, r) < 1)
      return 0.0;
   return r[0].close;
  }

int B100TrainScore(const B100Box &b, const double bid, const double ask, string &why)
  {
   why = "ok";
   if(bid <= 0.0 || ask < bid)
     {
      why = "tick_cross";
      return 0;
     }
   if(b.height <= 0.0 || b.bars < 3)
     {
      why = "box_invalid";
      return 0;
     }
   const double spread = ask - bid;
   if(spread > 0.25 * b.height)
     {
      why = "spread_vs_height";
      return 0;
     }
   if(b.height < 4.0 * spread)
     {
      why = "box_vs_spread";
      return 0;
     }
   return 1;
  }

void B100TrainArm(B100Episode &e, const B100Box &b, const double bid, const double ask, const int arm)
  {
   string why;
   const int q = B100TrainScore(b, bid, ask, why);
   ZeroMemory(e);
   e.active     = true;
   e.tracking   = false;
   e.quality    = q;
   e.q_reason   = why;
   e.armed_utc  = TimeGMT();
   e.armed_bar  = b.armed_bar;
   e.bars_box   = b.bars;
   e.height     = b.height;
   e.atr        = b.atr;
   e.spread_arm = ask - bid;
   e.buy_stop   = b.buy_stop;
   e.sell_stop  = b.sell_stop;
   e.hw         = b.height;
   e.arm        = arm;
   e.id         = (ulong)b.armed_bar;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   e.hour_gmt = dt.hour;
   e.dow      = dt.day_of_week;
   e.m1_rng   = B100TfRange(PERIOD_M1);
   e.m5_rng   = B100TfRange(PERIOD_M5);
   e.m30_rng  = B100TfRange(PERIOD_M30);
   const double h4c = B100TfClose(PERIOD_H4);
   const double mid = 0.5 * (b.high + b.low);
   e.h4_dist  = (h4c > 0.0 && b.height > 0.0) ? (mid - h4c) / b.height : 0.0;
   e.touches_hi = b.touches_hi;
   e.touches_lo = b.touches_lo;
   e.close_loc  = b.close_loc;
   e.compress   = b.compress;
   e.h_vs_h4    = b.h_vs_h4;
   e.imp_dir    = b.imp_dir;
   e.imp_h      = b.imp_h;
   e.imp_vs_box = b.imp_vs_box;
   e.box_at     = b.box_at;
   e.phase      = b.phase;
  }

void B100TrainWrite(const B100Episode &e)
  {
   const int fh = B100TrainFile();
   if(fh == INVALID_HANDLE)
      return;
   B100TrainEnsureHeader(fh);
   const double hw = MathMax(e.hw, 1e-9);
   const double mfe_r = e.mfe / hw;
   const double mae_r = MathAbs(e.mae) / hw;
   const double w = (e.quality == 1) ? 1.0 : 0.0;
   FileWrite(fh,
             e.side, e.label, e.mfe, e.mae, e.hw, e.arm, e.quality, e.exit_why,
             mfe_r, mae_r, e.height, e.atr, e.spread_arm, e.bars_box,
             e.hour_gmt, e.dow, e.hit_tp1, e.hit_tp2, e.hit_tp3, e.hit_sl,
             e.bars_held, w, (long)e.id, e.q_reason,
             e.buy_stop, e.sell_stop, e.entry, e.sl, e.tp1, e.tp2, e.tp3,
             e.touches_hi, e.touches_lo, e.close_loc, e.compress, e.h_vs_h4,
             e.imp_dir, e.imp_h, e.imp_vs_box, e.box_at, e.phase);
   FileClose(fh);
   const int kick = FileOpen("BREAK100_sync_needed.txt", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(kick != INVALID_HANDLE)
     {
      FileWriteString(kick, IntegerToString((int)TimeGMT()));
      FileClose(kick);
     }
  }

void B100TrainFail(B100Episode &e, const string label)
  {
   if(!e.active)
      return;
   e.side      = 0;
   e.label     = label;
   e.exit_why  = "TRAP";
   e.mfe       = 0.0;
   e.mae       = -e.hw;
   e.tracking  = false;
   B100TrainWrite(e);
   e.active = false;
  }

void B100TrainFill(B100Episode &e, const int side, const string label,
                   const double fill_px, const double sl, const double tp1, const double tp2, const double tp3)
  {
   if(!e.active)
      return;
   e.tracking = true;
   e.side     = side;
   e.label    = label;
   e.entry    = fill_px;
   e.sl       = sl;
   e.tp1      = tp1;
   e.tp2      = tp2;
   e.tp3      = tp3;
   e.fill_utc = TimeGMT();
   e.mfe      = 0.0;
   e.mae      = 0.0;
   e.bars_held = 0;
   e.last_bar = iTime(_Symbol, PERIOD_M30, 1);
   e.exit_why = "";
  }

bool B100TrainStep(B100Episode &e, const double bid, const double ask, const int horizon_bars)
  {
   if(!e.active || !e.tracking)
      return false;
   if(bid <= 0.0 || ask < bid)
      return false;

   const double px = (e.side > 0) ? bid : ask;
   double fav = (e.side > 0) ? (px - e.entry) : (e.entry - px);
   double adv = -fav;
   if(fav > e.mfe)
      e.mfe = fav;
   if(adv < e.mae)
      e.mae = adv;

   if(e.mfe >= MathAbs(e.tp1 - e.entry) && e.tp1 > 0.0)
      e.hit_tp1 = 1;
   if(e.mfe >= MathAbs(e.tp2 - e.entry) && e.tp2 > 0.0)
      e.hit_tp2 = 1;
   if(e.mfe >= MathAbs(e.tp3 - e.entry) && e.tp3 > 0.0)
      e.hit_tp3 = 1;

   const datetime bar = iTime(_Symbol, PERIOD_M30, 1);
   if(bar != 0 && bar != e.last_bar)
     {
      e.bars_held++;
      e.last_bar = bar;
     }

   bool sl_hit = false;
   if(e.side > 0 && bid <= e.sl)
      sl_hit = true;
   if(e.side < 0 && ask >= e.sl)
      sl_hit = true;
   if(sl_hit)
     {
      e.hit_sl = 1;
      e.exit_why = "SL";
      e.tracking = false;
      B100TrainWrite(e);
      e.active = false;
      return true;
     }
   if(e.hit_tp3)
     {
      e.exit_why = "TP3";
      e.tracking = false;
      B100TrainWrite(e);
      e.active = false;
      return true;
     }
   if(e.bars_held >= MathMax(2, horizon_bars))
     {
      if(e.hit_tp2)
         e.exit_why = "TP2_H";
      else if(e.hit_tp1)
         e.exit_why = "TP1_H";
      else
         e.exit_why = "HORIZON";
      e.tracking = false;
      B100TrainWrite(e);
      e.active = false;
      return true;
     }
   return false;
  }

void B100TrainBlotterStats(int &n_unique, int &n_sl, int &n_tp3)
  {
   n_unique = 0;
   n_sl = 0;
   n_tp3 = 0;
   string s = _Symbol;
   StringReplace(s, " ", "_");
   const int fh = FileOpen("BREAK100_train_" + s + ".csv",
                           FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(fh == INVALID_HANDLE)
      return;
   bool header = true;
   string seen = "|";
   while(!FileIsEnding(fh))
     {
      string line = FileReadString(fh);
      if(header)
        {
         header = false;
         continue;
        }
      if(StringLen(line) < 8)
         continue;
      string parts[];
      const int n = StringSplit(line, ',', parts);
      if(n < 24)
         continue;
      const int q = (int)StringToInteger(parts[6]);
      if(q != 1)
         continue;
      const string eid = parts[22];
      if(StringFind(seen, "|" + eid + "|") >= 0)
         continue;
      seen += eid + "|";
      n_unique++;
      const string ex = parts[7];
      if(ex == "SL" || ex == "CLOSE_SL")
         n_sl++;
      if(ex == "TP3")
         n_tp3++;
     }
   FileClose(fh);
  }

#endif
