//+------------------------------------------------------------------+
//|                                                   NewsFilter.mqh |
//|                                  Copyright 2026, LEE Sunghee     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, LEE Sunghee"
#property strict

class CNewsFilter
{
private:
   bool     m_enabled;
   int      m_minutes_before;
   int      m_minutes_after;

public:
   CNewsFilter(bool enabled = true, int minutes = 60)
   {
      m_enabled = enabled;
      m_minutes_before = minutes;
      m_minutes_after = minutes;
   }

   void SetEnabled(bool enabled) { m_enabled = enabled; }
   void SetWindow(int minutes) { m_minutes_before = minutes; m_minutes_after = minutes; }

   // Check if a currency is in High Impact news window (+/- minutes)
   bool IsCurrencyInNews(string currency, string &news_title, datetime &news_time)
   {
      if(!m_enabled || StringLen(currency) == 0)
         return false;

      datetime now = TimeCurrent();
      datetime date_from = now - (m_minutes_after * 60);
      datetime date_to   = now + (m_minutes_before * 60);

      MqlCalendarValue values[];
      ResetLastError();
      int count = CalendarValueHistory(values, date_from, date_to, NULL, currency);
      if(count <= 0)
         return false;

      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               news_title = event.name;
               news_time  = values[i].time;
               return true;
            }
         }
      }
      return false;
   }

   // Check if symbol (base or quote currency) is affected by high impact news
   bool IsSymbolInNews(string symbol, string &news_title, datetime &news_time)
   {
      if(!m_enabled)
         return false;

      string base_curr = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
      string quote_curr = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);

      if(IsCurrencyInNews(base_curr, news_title, news_time))
         return true;

      if(IsCurrencyInNews(quote_curr, news_title, news_time))
         return true;

      return false;
   }
};
