#ifndef BREAK100_CAPTURE_MQH
#define BREAK100_CAPTURE_MQH

// Pre-break warehouse: ticks + closed M1/M5/M15/M30/H4 + ARM setup + fill outcome.
// No broker orders.

#define B100_CAP_TFS     5
#define B100_TICK_BUF    256
#define B100_FLUSH_TICKS 200
#define B100_FLUSH_MS    1000

struct B100TickRow
  {
   long   utc_ms;
   double bid;
   double ask;
   double last;
   double volume;
   uint   flags;
  };

struct B100Capture
  {
   bool         enabled;
   string       symbol_key;
   string       day_key;
   int          tick_fh;
   int          bar_fh[B100_CAP_TFS];
   datetime     last_bar_time[B100_CAP_TFS];
   ulong        tick_count;
   ulong        tick_written;
   ulong        setup_n;
   ulong        outcome_n;
   uint         last_flush_ms;
   uint         last_reopen_ms;
   int          buf_n;
   B100TickRow  buf[B100_TICK_BUF];
  };

ENUM_TIMEFRAMES B100CapTf(const int i)
  {
   if(i == 1) return PERIOD_M5;
   if(i == 2) return PERIOD_M15;
   if(i == 3) return PERIOD_M30;
   if(i == 4) return PERIOD_H4;
   return PERIOD_M1;
  }

string B100CapTfName(const int i)
  {
   if(i == 1) return "M5";
   if(i == 2) return "M15";
   if(i == 3) return "M30";
   if(i == 4) return "H4";
   return "M1";
  }

string B100CapKey(void)
  {
   string s = _Symbol;
   StringReplace(s, " ", "_");
   return s;
  }

string B100CapDay(void)
  {
   string d = TimeToString(TimeGMT(), TIME_DATE);
   StringReplace(d, ".", "");
   return d;
  }

datetime B100BarGmt(const datetime server_time)
  {
   return server_time + (TimeGMT() - TimeCurrent());
  }

int B100CapOpenAppend(const string name)
  {
   return FileOpen(name, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, ',');
  }

void B100CapSeekEndOrHeader(const int fh, const string h1, const string h2, const string h3, const string h4, const string h5, const string h6)
  {
   if(fh == INVALID_HANDLE)
      return;
   if(FileSize(fh) == 0)
      FileWrite(fh, h1, h2, h3, h4, h5, h6);
   else
      FileSeek(fh, 0, SEEK_END);
  }

void B100CapClose(int &fh)
  {
   if(fh != INVALID_HANDLE)
     {
      FileFlush(fh);
      FileClose(fh);
      fh = INVALID_HANDLE;
     }
  }

void B100CapOpenTicks(B100Capture &c)
  {
   B100CapClose(c.tick_fh);
   c.day_key = B100CapDay();
   c.tick_fh = B100CapOpenAppend("BREAK100_ticks_" + c.symbol_key + "_" + c.day_key + ".csv");
   if(c.tick_fh == INVALID_HANDLE)
      return;
   if(FileSize(c.tick_fh) == 0)
      FileWrite(c.tick_fh, "utc_ms", "bid", "ask", "last", "volume", "flags");
   else
      FileSeek(c.tick_fh, 0, SEEK_END);
  }

void B100CapFlushTicks(B100Capture &c)
  {
   if(c.buf_n <= 0)
      return;
   if(c.tick_fh == INVALID_HANDLE)
      B100CapOpenTicks(c);
   if(c.tick_fh == INVALID_HANDLE)
     {
      c.buf_n = 0;
      return;
     }
   for(int i = 0; i < c.buf_n; i++)
     {
      FileWrite(c.tick_fh, c.buf[i].utc_ms, c.buf[i].bid, c.buf[i].ask,
                c.buf[i].last, c.buf[i].volume, (int)c.buf[i].flags);
      c.tick_written++;
     }
   c.buf_n = 0;
   FileFlush(c.tick_fh);
   c.last_flush_ms = GetTickCount();
  }

void B100CapWriteClosedBar(B100Capture &c, const int i)
  {
   if(c.bar_fh[i] == INVALID_HANDLE)
      return;
   MqlRates r[];
   if(CopyRates(_Symbol, B100CapTf(i), 1, 1, r) < 1)
      return;
   if(r[0].time <= c.last_bar_time[i])
      return;
   FileWrite(c.bar_fh[i],
             (long)B100BarGmt(r[0].time),
             TimeToString(B100BarGmt(r[0].time), TIME_DATE | TIME_SECONDS),
             r[0].open, r[0].high, r[0].low, r[0].close,
             r[0].tick_volume, r[0].spread, r[0].real_volume);
   c.last_bar_time[i] = r[0].time;
   FileFlush(c.bar_fh[i]);
  }

void B100CaptureInit(B100Capture &c, const bool on)
  {
   c.enabled = on;
   c.symbol_key = B100CapKey();
   c.day_key = B100CapDay();
   c.tick_fh = INVALID_HANDLE;
   c.tick_count = 0;
   c.tick_written = 0;
   c.setup_n = 0;
   c.outcome_n = 0;
   c.buf_n = 0;
   c.last_flush_ms = GetTickCount();
   c.last_reopen_ms = GetTickCount();
   for(int i = 0; i < B100_CAP_TFS; i++)
     {
      c.bar_fh[i] = INVALID_HANDLE;
      c.last_bar_time[i] = 0;
     }
   if(!on)
      return;
   B100CapOpenTicks(c);
   for(int i = 0; i < B100_CAP_TFS; i++)
     {
      c.bar_fh[i] = B100CapOpenAppend("BREAK100_bars_" + c.symbol_key + "_" + B100CapTfName(i) + ".csv");
      if(c.bar_fh[i] == INVALID_HANDLE)
         continue;
      if(FileSize(c.bar_fh[i]) == 0)
         FileWrite(c.bar_fh[i], "time_utc", "time_gmt", "open", "high", "low", "close",
                   "tick_volume", "spread", "real_volume");
      else
        {
         FileSeek(c.bar_fh[i], 0, SEEK_END);
         MqlRates r[];
         if(CopyRates(_Symbol, B100CapTf(i), 1, 1, r) >= 1)
            c.last_bar_time[i] = r[0].time;
        }
     }
   const int sh = B100CapOpenAppend("BREAK100_setup_" + c.symbol_key + ".csv");
   if(sh != INVALID_HANDLE)
     {
      if(FileSize(sh) == 0)
         FileWrite(sh,
                   "armed_utc", "armed_bar", "bid", "ask", "spread",
                   "high", "low", "height", "bars", "atr",
                   "buy_stop", "sell_stop", "t_left", "t_right",
                   "m1_o", "m1_h", "m1_l", "m1_c",
                   "m5_o", "m5_h", "m5_l", "m5_c",
                   "m15_o", "m15_h", "m15_l", "m15_c",
                   "m30_o", "m30_h", "m30_l", "m30_c",
                   "h4_o", "h4_h", "h4_l", "h4_c");
      FileClose(sh);
     }
   const int oh = B100CapOpenAppend("BREAK100_outcome_" + c.symbol_key + ".csv");
   if(oh != INVALID_HANDLE)
     {
      if(FileSize(oh) == 0)
         FileWrite(oh, "armed_bar", "fill_utc", "label", "side", "fill_bid", "fill_ask");
      FileClose(oh);
     }
  }

void B100CaptureDeinit(B100Capture &c)
  {
   if(c.enabled)
      B100CapFlushTicks(c);
   B100CapClose(c.tick_fh);
   for(int i = 0; i < B100_CAP_TFS; i++)
      B100CapClose(c.bar_fh[i]);
   c.enabled = false;
  }

void B100CaptureOnTick(B100Capture &c)
  {
   if(!c.enabled)
      return;
   if(B100CapDay() != c.day_key)
     {
      B100CapFlushTicks(c);
      B100CapOpenTicks(c);
     }
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick) && tick.bid > 0.0 && tick.ask >= tick.bid)
     {
      if(c.buf_n >= B100_TICK_BUF)
         B100CapFlushTicks(c);
      const int i = c.buf_n;
      c.buf[i].utc_ms = tick.time_msc;
      c.buf[i].bid = tick.bid;
      c.buf[i].ask = tick.ask;
      c.buf[i].last = tick.last;
      c.buf[i].volume = (double)tick.volume;
      c.buf[i].flags = tick.flags;
      c.buf_n++;
      c.tick_count++;
     }
   const uint now = GetTickCount();
   if(c.buf_n >= B100_FLUSH_TICKS || (now - c.last_flush_ms) >= B100_FLUSH_MS)
      B100CapFlushTicks(c);
   if((now - c.last_reopen_ms) >= 30000)
     {
      B100CapFlushTicks(c);
      B100CapOpenTicks(c);
      c.last_reopen_ms = now;
     }
   for(int i = 0; i < B100_CAP_TFS; i++)
      B100CapWriteClosedBar(c, i);
  }

bool B100CopyOHLC(const ENUM_TIMEFRAMES tf, double &o, double &h, double &l, double &cl)
  {
   MqlRates r[];
   o = h = l = cl = 0.0;
   if(CopyRates(_Symbol, tf, 1, 1, r) < 1)
      return false;
   o = r[0].open;
   h = r[0].high;
   l = r[0].low;
   cl = r[0].close;
   return true;
  }

void B100CaptureSetup(B100Capture &c, const B100Box &b, const double bid, const double ask)
  {
   if(!c.enabled)
      return;
   double m1o, m1h, m1l, m1c, m5o, m5h, m5l, m5c, m15o, m15h, m15l, m15c;
   double m30o, m30h, m30l, m30c, h4o, h4h, h4l, h4c;
   B100CopyOHLC(PERIOD_M1, m1o, m1h, m1l, m1c);
   B100CopyOHLC(PERIOD_M5, m5o, m5h, m5l, m5c);
   B100CopyOHLC(PERIOD_M15, m15o, m15h, m15l, m15c);
   B100CopyOHLC(PERIOD_M30, m30o, m30h, m30l, m30c);
   B100CopyOHLC(PERIOD_H4, h4o, h4h, h4l, h4c);
   const int fh = B100CapOpenAppend("BREAK100_setup_" + c.symbol_key + ".csv");
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   FileWrite(fh,
             TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
             (long)b.armed_bar, bid, ask, ask - bid,
             b.high, b.low, b.height, b.bars, b.atr,
             b.buy_stop, b.sell_stop, (long)b.t_left, (long)b.t_right,
             m1o, m1h, m1l, m1c,
             m5o, m5h, m5l, m5c,
             m15o, m15h, m15l, m15c,
             m30o, m30h, m30l, m30c,
             h4o, h4h, h4l, h4c);
   FileClose(fh);
   c.setup_n++;
  }

void B100CaptureOutcome(B100Capture &c, const B100Box &b, const string label, const double bid, const double ask)
  {
   if(!c.enabled)
      return;
   const int fh = B100CapOpenAppend("BREAK100_outcome_" + c.symbol_key + ".csv");
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   FileWrite(fh, (long)b.armed_bar,
             TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
             label, b.last_side, bid, ask);
   FileClose(fh);
   c.outcome_n++;
  }

#endif
