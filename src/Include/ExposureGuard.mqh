//+------------------------------------------------------------------+
//|                                                ExposureGuard.mqh |
//|                                  Copyright 2026, LEE Sunghee     |
//+------------------------------------------------------------------+
//  v2.0 – Apply max-basket limit to ALL quote currencies (not just JPY/NZD/SGD)
//          Max concurrent baskets per quote currency: 4
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, LEE Sunghee"
#property strict

#include <Trade\PositionInfo.mqh>

class CExposureGuard
{
private:
   CPositionInfo  m_position;

public:
   CExposureGuard() {}

   // Extract quote/profit currency from symbol (e.g., "JPY", "USD", "EUR")
   string GetQuoteCurrency(string symbol)
   {
      // Primary source: terminal metadata
      string profit_curr = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      if(StringLen(profit_curr) > 0)
         return profit_curr;

      // Fallback: parse last 3 chars of base symbol (strip broker suffix like .p, .m)
      string clean = symbol;
      int dot_idx = StringFind(clean, ".");
      if(dot_idx > 0) clean = StringSubstr(clean, 0, dot_idx);
      if(StringLen(clean) >= 6)
         return StringSubstr(clean, 3, 3);

      return "";
   }

   // Count unique symbols (baskets) with a specific quote currency under this magic number
   int CountActiveBasketsByQuote(string quote_curr, ulong magic)
   {
      string counted_symbols[];
      ArrayResize(counted_symbols, 0);

      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         if(!m_position.SelectByIndex(i))
            continue;

         if(m_position.Magic() == magic)
         {
            string pos_sym   = m_position.Symbol();
            string pos_quote = GetQuoteCurrency(pos_sym);

            if(pos_quote == quote_curr)
            {
               // Count each symbol only once (basket = all positions for one symbol)
               bool exists = false;
               for(int j = 0; j < ArraySize(counted_symbols); j++)
               {
                  if(counted_symbols[j] == pos_sym) { exists = true; break; }
               }
               if(!exists)
               {
                  int sz = ArraySize(counted_symbols);
                  ArrayResize(counted_symbols, sz + 1);
                  counted_symbols[sz] = pos_sym;
               }
            }
         }
      }
      return ArraySize(counted_symbols);
   }

   // Verify whether a new Level-1 basket can be opened for the given symbol.
   // Rule: For EVERY quote currency, max concurrent baskets = max_quote_baskets (default 4).
   bool CanOpenNewBasket(string symbol, ulong magic, int max_quote_baskets, string &reject_reason)
   {
      string quote = GetQuoteCurrency(symbol);
      if(StringLen(quote) == 0)
         return true; // Cannot determine quote currency; allow entry

      int active_count = CountActiveBasketsByQuote(quote, magic);
      if(active_count >= max_quote_baskets)
      {
         reject_reason = StringFormat(
            "Quote currency %s limit reached (%d/%d active baskets). Waiting for a basket to close.",
            quote, active_count, max_quote_baskets);
         return false;
      }

      return true;
   }
};
