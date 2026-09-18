//+------------------------------------------------------------------+
//|                                                ExposureGuard.mqh |
//|                                  Copyright 2026, LEE Sunghee     |
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

   // Extract quote/profit currency (e.g., JPY, NZD, SGD, USD)
   string GetQuoteCurrency(string symbol)
   {
      string profit_curr = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      if(StringLen(profit_curr) > 0)
         return profit_curr;

      // Fallback substring parser if SYMBOL_CURRENCY_PROFIT is empty
      string clean = symbol;
      int dot_idx = StringFind(clean, ".");
      if(dot_idx > 0) clean = StringSubstr(clean, 0, dot_idx);
      if(StringLen(clean) >= 6)
         return StringSubstr(clean, 3, 3);
      
      return "";
   }

   // Count active martingale baskets that share a specific quote currency
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
            string pos_sym = m_position.Symbol();
            string pos_quote = GetQuoteCurrency(pos_sym);

            if(pos_quote == quote_curr)
            {
               // Check if symbol was already counted
               bool exists = false;
               for(int j = 0; j < ArraySize(counted_symbols); j++)
               {
                  if(counted_symbols[j] == pos_sym)
                  {
                     exists = true;
                     break;
                  }
               }
               if(!exists)
               {
                  int new_size = ArraySize(counted_symbols) + 1;
                  ArrayResize(counted_symbols, new_size);
                  counted_symbols[new_size - 1] = pos_sym;
               }
            }
         }
      }
      return ArraySize(counted_symbols);
   }

   // Verify if a new Level 1 basket can be opened for the given symbol
   bool CanOpenNewBasket(string symbol, ulong magic, int max_quote_baskets, string &reject_reason)
   {
      string quote = GetQuoteCurrency(symbol);

      // Concentration restriction applies specifically to JPY, NZD, SGD
      if(quote == "JPY" || quote == "NZD" || quote == "SGD")
      {
         int active_count = CountActiveBasketsByQuote(quote, magic);
         if(active_count >= max_quote_baskets)
         {
            reject_reason = StringFormat("Quote currency %s limit reached (%d/%d active baskets)", quote, active_count, max_quote_baskets);
            return false;
         }
      }

      return true;
   }
};
