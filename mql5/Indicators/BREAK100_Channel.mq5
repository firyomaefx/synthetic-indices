#property copyright "BREAK100"
#property version   "1.00"
#property description "Visual-only BREAK100 causal channel. No orders."
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "Centre"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSilver
#property indicator_style1  STYLE_DOT
#property indicator_width1  1

#property indicator_label2  "Upper"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'139,144,160'
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Lower"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'139,144,160'
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#include <Break100/Channel.mqh>

input int    InpMadWindow     = 160;
input double InpKalmanQ       = 0.08;
input double InpKalmanRFloor  = 0.04;
input double InpMadK          = 2.4;

double         g_centre[];
double         g_upper[];
double         g_lower[];
B100Pipe       g_pipe;
bool           g_pipe_ready = false;

int OnInit()
  {
   SetIndexBuffer(0, g_centre, INDICATOR_DATA);
   SetIndexBuffer(1, g_upper,  INDICATOR_DATA);
   SetIndexBuffer(2, g_lower,  INDICATOR_DATA);
   ArraySetAsSeries(g_centre, false);
   ArraySetAsSeries(g_upper,  false);
   ArraySetAsSeries(g_lower,  false);
   IndicatorSetString(INDICATOR_SHORTNAME, "BREAK100 Channel");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   g_pipe_ready = false;
   return INIT_SUCCEEDED;
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 20)
      return 0;

   const bool full = (prev_calculated <= 0 || !g_pipe_ready);
   int start = 0;
   if(full)
     {
      B100PipeInit(g_pipe, close[0], InpMadWindow, InpKalmanQ, InpKalmanRFloor, InpMadK, 6, 48);
      g_pipe_ready = true;
      start = 0;
     }
   else
      start = prev_calculated - 1;

   for(int i = start; i < rates_total; i++)
     {
      const int spr_points = (spread[i] > 0) ? spread[i] : 1;
      const double spr = spr_points * _Point;
      const double mid = close[i];
      const double bid = mid - 0.5 * spr;
      const double ask = mid + 0.5 * spr;
      B100Ingest(g_pipe, bid, ask);
      g_centre[i] = g_pipe.kalman_x;
      g_upper[i]  = g_pipe.kalman_x + g_pipe.half_width;
      g_lower[i]  = g_pipe.kalman_x - g_pipe.half_width;
     }
   return rates_total;
  }
