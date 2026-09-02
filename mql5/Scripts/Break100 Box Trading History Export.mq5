#property copyright "Break100 Box Trading"
#property version   "1.00"
#property script_show_inputs
#property description "Export maximum available bar and tick history to Common\\Files for offline research."
#property description "Read-only: sends no orders and never writes to the live capture files."

// Writes BREAK100_hist_<SYM>_<TF>.csv and BREAK100_histticks_<SYM>_<YYYYMMDD>.csv.
// The 'hist_' prefix is deliberate: Capture.mqh appends to BREAK100_bars_* and
// BREAK100_ticks_* while the EA runs, and this script must never truncate those.
// The research harness merges both sources offline.

input string          InpSymbol      = "";        // Symbol ("" = current chart)
input bool            InpExportBars  = true;      // Export M1/M5/M15/M30/H1/H4 bars
input bool            InpExportTicks = true;      // Export ticks (large)
input int             InpTickDays    = 60;        // Days of tick history to attempt
input int             InpMaxBars     = 2000000;   // Safety ceiling per timeframe

const ENUM_TIMEFRAMES B100_TFS[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4};

string B100TfTag(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
     }
   return EnumToString(tf);
  }

string B100SymKey(const string sym)
  {
   string s = sym;
   StringReplace(s, " ", "_");
   return s;
  }

// MT5 loads history lazily. Poke the series, then wait for the server to sync
// before trusting Bars() — otherwise the first call reports a truncated depth.
bool B100WaitSeries(const string sym, const ENUM_TIMEFRAMES tf, const int timeout_ms)
  {
   MqlRates probe[];
   CopyRates(sym, tf, 0, 1, probe);
   const uint deadline = GetTickCount() + (uint)timeout_ms;
   while(GetTickCount() < deadline)
     {
      if(IsStopped())
         return false;
      if((bool)SeriesInfoInteger(sym, tf, SERIES_SYNCHRONIZED))
         return true;
      CopyRates(sym, tf, 0, 1, probe);
      Sleep(200);
     }
   return (Bars(sym, tf) > 0);
  }

int B100ExportBars(const string sym, const ENUM_TIMEFRAMES tf)
  {
   if(!B100WaitSeries(sym, tf, 15000))
     {
      PrintFormat("BREAK100 export %s: series not synchronised", B100TfTag(tf));
      return 0;
     }
   const int total = (int)MathMin((double)Bars(sym, tf), (double)InpMaxBars);
   if(total <= 0)
     {
      PrintFormat("BREAK100 export %s: no bars", B100TfTag(tf));
      return 0;
     }

   const string fname = "BREAK100_hist_" + B100SymKey(sym) + "_" + B100TfTag(tf) + ".csv";
   const int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
     {
      PrintFormat("BREAK100 export %s: cannot open %s (%d)", B100TfTag(tf), fname, GetLastError());
      return 0;
     }
   // Schema matches Capture.mqh's BREAK100_bars_* so both merge without a shim.
   FileWrite(fh, "time_utc", "time_gmt", "open", "high", "low", "close",
             "tick_volume", "spread", "real_volume");

   int written = 0;
   const int chunk = 50000;
   for(int pos = total - 1; pos >= 0; )
     {
      const int want = (int)MathMin((double)chunk, (double)(pos + 1));
      const int start = pos - want + 1;
      MqlRates r[];
      ArraySetAsSeries(r, false);
      const int got = CopyRates(sym, tf, start, want, r);
      if(got <= 0)
         break;
      for(int i = 0; i < got; i++)
         FileWrite(fh, (long)r[i].time, TimeToString(r[i].time, TIME_DATE | TIME_SECONDS),
                   DoubleToString(r[i].open, _Digits), DoubleToString(r[i].high, _Digits),
                   DoubleToString(r[i].low, _Digits), DoubleToString(r[i].close, _Digits),
                   (long)r[i].tick_volume, (int)r[i].spread, (long)r[i].real_volume);
      written += got;
      pos -= got;
      if(IsStopped())
         break;
     }
   FileClose(fh);
   PrintFormat("BREAK100 export %-3s  %d bars -> %s", B100TfTag(tf), written, fname);
   return written;
  }

int B100ExportTicks(const string sym, const int days)
  {
   const datetime now = TimeCurrent();
   int total = 0;
   for(int d = days; d >= 0; d--)
     {
      if(IsStopped())
         break;
      const datetime day0 = (datetime)(((long)(now - d * 86400) / 86400) * 86400);
      const long from_ms = (long)day0 * 1000;
      const long to_ms   = from_ms + 86400000 - 1;

      MqlTick ticks[];
      const int got = CopyTicksRange(sym, ticks, COPY_TICKS_ALL, from_ms, to_ms);
      if(got <= 0)
         continue;

      MqlDateTime dt;
      TimeToStruct(day0, dt);
      const string fname = StringFormat("BREAK100_histticks_%s_%04d%02d%02d.csv",
                                        B100SymKey(sym), dt.year, dt.mon, dt.day);
      const int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(fh == INVALID_HANDLE)
         continue;
      FileWrite(fh, "utc_ms", "bid", "ask", "last", "volume", "flags");
      for(int i = 0; i < got; i++)
         FileWrite(fh, (long)ticks[i].time_msc,
                   DoubleToString(ticks[i].bid, _Digits),
                   DoubleToString(ticks[i].ask, _Digits),
                   DoubleToString(ticks[i].last, _Digits),
                   (long)ticks[i].volume, (int)ticks[i].flags);
      FileClose(fh);
      total += got;
      PrintFormat("BREAK100 export ticks %s  %d -> %s", TimeToString(day0, TIME_DATE), got, fname);
     }
   return total;
  }

void OnStart()
  {
   const string sym = (InpSymbol == "" ? _Symbol : InpSymbol);
   if(!SymbolSelect(sym, true))
     {
      PrintFormat("BREAK100 export: unknown symbol '%s'", sym);
      return;
     }
   PrintFormat("BREAK100 export start  symbol=%s  ticks=%s  bars=%s",
               sym, (InpExportTicks ? "yes" : "no"), (InpExportBars ? "yes" : "no"));

   int bars = 0;
   if(InpExportBars)
      for(int i = 0; i < ArraySize(B100_TFS); i++)
         bars += B100ExportBars(sym, B100_TFS[i]);

   int ticks = 0;
   if(InpExportTicks)
      ticks = B100ExportTicks(sym, MathMax(1, InpTickDays));

   PrintFormat("BREAK100 export done  bars=%d  ticks=%d  -> %s",
               bars, ticks, TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files");
  }
