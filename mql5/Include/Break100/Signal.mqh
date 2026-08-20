#ifndef BREAK100_SIGNAL_MQH
#define BREAK100_SIGNAL_MQH

// Signal contract to Common Files. No execution.

void B100JsonEscape(string &s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
  }

void B100WriteSignalJson(const string action,
                         const double entry,
                         const double sl,
                         const double tp1,
                         const double tp2,
                         const double lots,
                         const double risk_amt,
                         const double rr,
                         const double ev,
                         const string reason,
                         const string signal_id,
                         const string model)
  {
   string r = reason;
   B100JsonEscape(r);
   string line = "{";
   line += "\"signal_id\":\"" + signal_id + "\",";
   line += "\"timestamp\":\"" + TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS) + "\",";
   line += "\"symbol\":\"" + _Symbol + "\",";
   line += "\"action\":\"" + action + "\",";
   line += "\"entry\":" + DoubleToString(entry, _Digits) + ",";
   line += "\"stop_loss\":" + DoubleToString(sl, _Digits) + ",";
   line += "\"take_profit_1\":" + DoubleToString(tp1, _Digits) + ",";
   line += "\"take_profit_2\":" + DoubleToString(tp2, _Digits) + ",";
   line += "\"position_size\":" + DoubleToString(lots, 2) + ",";
   line += "\"risk_amount\":" + DoubleToString(risk_amt, 2) + ",";
   line += "\"reward_to_risk\":" + DoubleToString(rr, 3) + ",";
   line += "\"expected_value\":" + DoubleToString(ev, 4) + ",";
   line += "\"confidence\":null,";
   line += "\"uncertainty\":null,";
   line += "\"model_version\":\"" + model + "\",";
   line += "\"reason\":\"" + r + "\"}";
   string fname = "BREAK100_signal_" + _Symbol + ".jsonl";
   StringReplace(fname, " ", "_");
   const int fh = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   FileWriteString(fh, line + "\n");
   FileClose(fh);
  }

#endif
