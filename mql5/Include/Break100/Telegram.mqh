#ifndef BREAK100_TELEGRAM_MQH
#define BREAK100_TELEGRAM_MQH

// Sends alerts via Bot API. Token/chat live in Common Files, not in git.

string g_tg_token = "";
string g_tg_chat  = "";
bool   g_tg_ok    = false;

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
   if(g_tg_ok)
      Print("B100 Telegram enabled chat=", g_tg_chat);
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

bool B100TelegramSend(string text)
  {
   if(!g_tg_ok)
      return false;
   uchar data[];
   uchar result[];
   const string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string result_headers = "";
   string body = "chat_id=" + B100UrlEnc(g_tg_chat) + "&text=" + B100UrlEnc(text);
   StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
   int n = ArraySize(data);
   if(n > 0 && data[n - 1] == 0)
      ArrayResize(data, n - 1);
   string url = "https://api.telegram.org/bot" + g_tg_token + "/sendMessage";
   ResetLastError();
   const int code = WebRequest("POST", url, headers, 4000, data, result, result_headers);
   if(code != 200)
     {
      Print("B100 Telegram HTTP ", code, " err=", GetLastError());
      return false;
     }
   return true;
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
   if(!g_tg_ok || text == "")
      return false;
   if(B100TgSeen(key))
      return false;
   B100TgRemember(key);
   return B100TelegramSend(text);
  }

#endif
