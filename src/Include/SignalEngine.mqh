//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|                                  Copyright 2026, LEE Sunghee     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, LEE Sunghee"
#property strict

#include "TradeManager.mqh"

class CSignalEngine
{
private:
   int   m_ema_period;
   int   m_atr_period;
   int   m_rsi_period;

public:
   CSignalEngine(int ema_period = 30, int atr_period = 14, int rsi_period = 14)
   {
      m_ema_period = ema_period;
      m_atr_period = atr_period;
      m_rsi_period = rsi_period;
   }

   // Return point value for 1 pip (e.g., 0.0001 = 10 points for 5 digits, 0.01 = 10 points for 3 digits)
   double GetPipSize(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits   = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(digits == 3 || digits == 5)
         return point * 10.0;
      return point;
   }

   // Convert pips to price distance
   double PipsToPrice(string symbol, double pips)
   {
      return pips * GetPipSize(symbol);
   }

   // Convert price difference to pips
   double PriceToPips(string symbol, double price_diff)
   {
      double pip_size = GetPipSize(symbol);
      if(pip_size <= 0) return 0.0;
      return price_diff / pip_size;
   }

   // Calculate dynamic TP in pips (50 ~ 500 pips) based on M15 ATR
   double CalculateDynamicTPPips(string symbol)
   {
      int handle = iATR(symbol, PERIOD_M15, m_atr_period);
      if(handle == INVALID_HANDLE)
         return 50.0;

      double atr_val[];
      ArraySetAsSeries(atr_val, true);
      if(CopyBuffer(handle, 0, 1, 1, atr_val) <= 0)
      {
         IndicatorRelease(handle);
         return 50.0;
      }
      IndicatorRelease(handle);

      double atr_pips = PriceToPips(symbol, atr_val[0]);
      double dynamic_tp = atr_pips * 3.0; // 3x ATR target

      if(dynamic_tp < 50.0)  dynamic_tp = 50.0;
      if(dynamic_tp > 500.0) dynamic_tp = 500.0;

      return dynamic_tp;
   }

   // Check initial entry signal (Level 1) based on 15M 30-EMA
   bool CheckInitialSignal(string symbol, ENUM_POSITION_TYPE &signal)
   {
      signal = WRONG_VALUE;
      int handle = iMA(symbol, PERIOD_M15, m_ema_period, 0, MODE_EMA, PRICE_CLOSE);
      if(handle == INVALID_HANDLE)
         return false;

      double ema[];
      ArraySetAsSeries(ema, true);
      if(CopyBuffer(handle, 0, 1, 2, ema) < 2)
      {
         IndicatorRelease(handle);
         return false;
      }
      IndicatorRelease(handle);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, PERIOD_M15, 1, 3, rates) < 3)
         return false;

      // rates[0] is Bar 1 (closed), rates[1] is Bar 2, rates[2] is Bar 3
      double close1 = rates[0].close;
      double open1  = rates[0].open;
      double close2 = rates[1].close;
      double ema1   = ema[0];
      double ema2   = ema[1];

      // Bullish condition:
      // 1) Bar 1 crossed above 30-EMA OR
      // 2) Bar 1 pulled back to 30-EMA (Low near EMA) and closed as a strong bullish candle above EMA
      bool cross_up = (close2 <= ema2 && close1 > ema1);
      bool bounce_up = (rates[0].low <= ema1 && close1 > ema1 && close1 > open1);

      if(cross_up || bounce_up)
      {
         signal = POSITION_TYPE_BUY;
         return true;
      }

      // Bearish condition:
      // 1) Bar 1 crossed below 30-EMA OR
      // 2) Bar 1 pulled back to 30-EMA (High near EMA) and closed as a strong bearish candle below EMA
      bool cross_down = (close2 >= ema2 && close1 < ema1);
      bool bounce_down = (rates[0].high >= ema1 && close1 < ema1 && close1 < open1);

      if(cross_down || bounce_down)
      {
         signal = POSITION_TYPE_SELL;
         return true;
      }

      return false;
   }

   // Get required distance in pips for subsequent martingale levels (Expanding Grid)
   double GetRequiredLevelDistancePips(int next_level)
   {
      switch(next_level)
      {
         case 2: return 35.0;
         case 3: return 45.0;
         case 4: return 65.0;
         case 5: return 90.0;
         case 6: return 125.0;
         case 7: return 175.0;
         case 8: return 250.0;
         default: return 9999.0; // Level 9+ is blocked
      }
   }

   // Check if technical reversal conditions are met for martingale entry
   bool CheckReversalConfirmation(string symbol, ENUM_POSITION_TYPE pos_type, int next_level)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, PERIOD_M15, 1, 2, rates) < 2)
         return false;

      // Levels 2-3: Basic candlestick reversal (Bullish candle for BUY, Bearish for SELL)
      if(next_level <= 3)
      {
         if(pos_type == POSITION_TYPE_BUY)
            return (rates[0].close > rates[0].open);
         else
            return (rates[0].close < rates[0].open);
      }

      // Levels 4-5: RSI(14) oversold/overbought hook
      if(next_level <= 5)
      {
         int rsi_handle = iRSI(symbol, PERIOD_M15, m_rsi_period, PRICE_CLOSE);
         if(rsi_handle == INVALID_HANDLE) return true;

         double rsi[];
         ArraySetAsSeries(rsi, true);
         bool ok = false;
         if(CopyBuffer(rsi_handle, 0, 1, 2, rsi) >= 2)
         {
            if(pos_type == POSITION_TYPE_BUY)
               ok = (rsi[0] > rsi[1] && rsi[1] < 35.0); // Turning up from oversold
            else
               ok = (rsi[0] < rsi[1] && rsi[1] > 65.0); // Turning down from overbought
         }
         IndicatorRelease(rsi_handle);
         return ok;
      }

      // Levels 6-8: Ultra-conservative reversal (Higher Timeframe H1 candle or strict M15 2 consecutive reversal bars)
      if(next_level <= 8)
      {
         MqlRates h1_rates[];
         ArraySetAsSeries(h1_rates, true);
         if(CopyRates(symbol, PERIOD_H1, 1, 1, h1_rates) >= 1)
         {
            if(pos_type == POSITION_TYPE_BUY)
               return (h1_rates[0].close > h1_rates[0].open);
            else
               return (h1_rates[0].close < h1_rates[0].open);
         }
      }

      return false;
   }

   // Check if basket is eligible for next martingale level
   bool CanAddMartingaleLevel(string symbol, const BasketInfo &basket, int &next_level, string &reason)
   {
      next_level = basket.count + 1;
      if(next_level > 8)
      {
         reason = "Maximum allowed martingale levels (8) reached. No further entries allowed.";
         return false;
      }

      double req_pips = GetRequiredLevelDistancePips(next_level);
      double current_price = (basket.pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      double adverse_pips = 0.0;
      if(basket.pos_type == POSITION_TYPE_BUY)
         adverse_pips = PriceToPips(symbol, basket.last_open_price - current_price);
      else
         adverse_pips = PriceToPips(symbol, current_price - basket.last_open_price);

      if(adverse_pips < req_pips)
      {
         reason = StringFormat("Adverse distance (%.1f pips) < Required distance (%.1f pips) for Level %d", adverse_pips, req_pips, next_level);
         return false;
      }

      if(!CheckReversalConfirmation(symbol, basket.pos_type, next_level))
      {
         reason = StringFormat("Distance met (%.1f pips), waiting for reversal confirmation signal for Level %d", adverse_pips, next_level);
         return false;
      }

      return true;
   }
};
