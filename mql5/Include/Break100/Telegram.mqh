#ifndef BREAK100_TELEGRAM_MQH
#define BREAK100_TELEGRAM_MQH

// Sends alerts via Bot API. Token/chat live in Common Files, not in git.

string   g_tg_token = "";
string   g_tg_chat  = "";
bool     g_tg_ok    = false;
datetime g_tg_session = 0;
int      g_tg_day_n   = 0;
int      g_tg_signal_n = 0;

void B100TgDayLoad(void);
void B100TgDayEnsure(void);

void B100TelegramLoad(void)
  {
   g_tg_ok = false;
   g_tg_token = "";
   g_tg_chat = "";
   const int fh = FileOpen("BREAK100_telegram.txt", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(fh == INVALID_HANDLE)
      return;
   while(!FileIsEnding(fh))
     {
      string line = FileReadString(fh);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringFind(line, "token=") == 0)
         g_tg_token = StringSubstr(line, 6);
      else if(StringFind(line, "chat=") == 0)
         g_tg_chat = StringSubstr(line, 5);
     }
   FileClose(fh);
   g_tg_ok = (StringLen(g_tg_token) > 10 && StringLen(g_tg_chat) > 0);
   B100TgDayLoad();
   B100TgDayEnsure();
   if(g_tg_ok)
      Print("B100 Telegram enabled chat=", g_tg_chat,
            "  session=", TimeToString(g_tg_session, TIME_DATE | TIME_MINUTES), " GMT",
            "  signals=", g_tg_day_n);
   else
      Print("B100 Telegram off — put token= and chat= in Common\\Files\\BREAK100_telegram.txt");
  }

string B100UrlEnc(string s)
  {
   StringReplace(s, "%", "%25");
   StringReplace(s, " ", "%20");
   StringReplace(s, "\n", "%0A");
   StringReplace(s, "&", "%26");
   StringReplace(s, "+", "%2B");
   StringReplace(s, "=", "%3D");
   return s;
  }

long B100TgParseMsgId(const uchar &result[])
  {
   string json = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   const int p = StringFind(json, "\"message_id\":");
   if(p < 0)
      return 0;
   int i = p + 13;
   while(i < StringLen(json) && (StringGetCharacter(json, i) == ' ' || StringGetCharacter(json, i) == '\t'))
      i++;
   long id = 0;
   while(i < StringLen(json))
     {
      const ushort ch = (ushort)StringGetCharacter(json, i);
      if(ch < '0' || ch > '9')
         break;
      id = id * 10 + (ch - '0');
      i++;
     }
   return id;
  }

long B100TelegramSendReply(string text, const long reply_to)
  {
   if(!g_tg_ok || text == "")
      return 0;
   uchar data[];
   uchar result[];
   const string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string result_headers = "";
   string body = "chat_id=" + B100UrlEnc(g_tg_chat) + "&text=" + B100UrlEnc(text);
   if(reply_to > 0)
      body += "&reply_to_message_id=" + IntegerToString((int)reply_to);
   StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
   int n = ArraySize(data);
   if(n > 0 && data[n - 1] == 0)
      ArrayResize(data, n - 1);
   string url = "https://api.telegram.org/bot" + g_tg_token + "/sendMessage";
   ResetLastError();
   const int code = WebRequest("POST", url, headers, 1500, data, result, result_headers);
   if(code != 200)
     {
      Print("B100 Telegram HTTP ", code, " err=", GetLastError());
      return 0;
     }
   return B100TgParseMsgId(result);
  }

bool B100TelegramSend(string text)
  {
   return (B100TelegramSendReply(text, 0) > 0);
  }

string B100TgOnceFile(void)
  {
   return "BREAK100_tg_once.txt";
  }

bool B100TgSeen(const string key)
  {
   if(key == "")
      return false;
   const int fh = FileOpen(B100TgOnceFile(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(fh == INVALID_HANDLE)
      return false;
   bool seen = false;
   while(!FileIsEnding(fh))
     {
      string line = FileReadString(fh);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(line == key)
        {
         seen = true;
         break;
        }
     }
   FileClose(fh);
   return seen;
  }

void B100TgRemember(const string key)
  {
   const int fh = FileOpen(B100TgOnceFile(), FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return;
   FileSeek(fh, 0, SEEK_END);
   FileWriteString(fh, key + "\n");
   FileClose(fh);
  }

bool B100TelegramOnce(const string key, const string text)
  {
   return (B100TelegramOnceReply(key, text, 0) > 0);
  }

datetime B100TgSessionStart(const datetime gmt)
  {
   MqlDateTime dt;
   TimeToStruct(gmt, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   const datetime midnight = StructToTime(dt);
   datetime six = midnight + 6 * 3600;
   if(gmt < six)
      six -= 24 * 3600;
   return six;
  }

void B100TgDaySave(void)
  {
   const int fh = FileOpen("BREAK100_tg_day.txt", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return;
   FileWriteString(fh, "session=" + IntegerToString((int)g_tg_session) + "\n");
   FileWriteString(fh, "n=" + IntegerToString(g_tg_day_n) + "\n");
   FileWriteString(fh, "cur=" + IntegerToString(g_tg_signal_n) + "\n");
   FileClose(fh);
  }

void B100TgDayLoad(void)
  {
   const int fh = FileOpen("BREAK100_tg_day.txt", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(fh == INVALID_HANDLE)
      return;
   while(!FileIsEnding(fh))
     {
      string line = FileReadString(fh);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringFind(line, "session=") == 0)
         g_tg_session = (datetime)StringToInteger(StringSubstr(line, 8));
      else if(StringFind(line, "n=") == 0)
         g_tg_day_n = (int)StringToInteger(StringSubstr(line, 2));
      else if(StringFind(line, "cur=") == 0)
         g_tg_signal_n = (int)StringToInteger(StringSubstr(line, 4));
     }
   FileClose(fh);
  }

void B100TgDayEnsure(void)
  {
   const datetime start = B100TgSessionStart(TimeGMT());
   if(g_tg_session != start)
     {
      g_tg_session = start;
      g_tg_day_n = 0;
      g_tg_signal_n = 0;
      B100TgDaySave();
      Print("B100 Telegram day reset  session=", TimeToString(start, TIME_DATE | TIME_MINUTES), " GMT");
     }
  }

int B100TgDayBump(void)
  {
   B100TgDayEnsure();
   g_tg_day_n++;
   g_tg_signal_n = g_tg_day_n;
   B100TgDaySave();
   return g_tg_signal_n;
  }

string B100TgSigHead(const bool new_signal)
  {
   B100TgDayEnsure();
   if(new_signal)
      B100TgDayBump();
   if(g_tg_signal_n <= 0)
      return "";
   string s = "📋 Signal " + IntegerToString(g_tg_signal_n);
   s += "   day " + TimeToString(g_tg_session, TIME_DATE | TIME_MINUTES) + " GMT\n";
   return s;
  }

long B100TelegramOnceReply(const string key, const string text, const long reply_to)
  {
   if(!g_tg_ok || text == "")
      return 0;
   if(B100TgSeen(key))
      return 0;
   long id = B100TelegramSendReply(text, reply_to);
   if(id <= 0 && reply_to > 0)
      id = B100TelegramSendReply(text, 0);
   if(id > 0)
      B100TgRemember(key);
   return id;
  }

#endif
