//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|                                  Copyright 2026, LEE Sunghee     |
//+------------------------------------------------------------------+
//  v2.0 – Basket target in USD; conservative martingale entry weights;
//          RSI prerequisite for all martingale levels; expanded grid distances.
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

   //--------------------------------------------------------------------
   // Pip utilities
   //--------------------------------------------------------------------

   // Size of 1 pip in price units
   double GetPipSize(string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(digits == 3 || digits == 5)
         return point * 10.0;
      return point;
   }

   double PipsToPrice(string symbol, double pips)  { return pips * GetPipSize(symbol); }
   double PriceToPips(string symbol, double diff)
   {
      double ps = GetPipSize(symbol);
      return (ps > 0) ? diff / ps : 0.0;
   }

   //--------------------------------------------------------------------
   // Dynamic TP for single Level-1 position (ATR × 3, clamped 50-500 pip)
   //--------------------------------------------------------------------
   double CalculateDynamicTPPips(string symbol)
   {
      int handle = iATR(symbol, PERIOD_M15, m_atr_period);
      if(handle == INVALID_HANDLE) return 50.0;

      double atr[];
      ArraySetAsSeries(atr, true);
      double result = 50.0;
      if(CopyBuffer(handle, 0, 1, 1, atr) > 0)
      {
         double pips = PriceToPips(symbol, atr[0]) * 3.0;
         result = MathMax(50.0, MathMin(500.0, pips));
      }
      IndicatorRelease(handle);
      return result;
   }

   //--------------------------------------------------------------------
   // RSI helper – returns current RSI value on M15, bar 1 (closed)
   //--------------------------------------------------------------------
   double GetRSI(string symbol, ENUM_TIMEFRAMES tf = PERIOD_M15, int bar = 1)
   {
      int h = iRSI(symbol, tf, m_rsi_period, PRICE_CLOSE);
      if(h == INVALID_HANDLE) return 50.0;

      double rsi[];
      ArraySetAsSeries(rsi, true);
      double val = 50.0;
      if(CopyBuffer(h, 0, bar, 1, rsi) > 0) val = rsi[0];
      IndicatorRelease(h);
      return val;
   }

   // Returns true when RSI hooks in the expected direction from an extreme
   // (uses bar 1 = current closed bar and bar 2 = previous bar)
   bool RSIHook(string symbol, ENUM_POSITION_TYPE pos_type,
                double extreme_level_high, double extreme_level_low,
                ENUM_TIMEFRAMES tf = PERIOD_M15)
   {
      int h = iRSI(symbol, tf, m_rsi_period, PRICE_CLOSE);
      if(h == INVALID_HANDLE) return false;

      double rsi[];
      ArraySetAsSeries(rsi, true);
      bool ok = false;
      if(CopyBuffer(h, 0, 1, 2, rsi) >= 2)
      {
         if(pos_type == POSITION_TYPE_BUY)
            ok = (rsi[1] <= extreme_level_low && rsi[0] > rsi[1]); // turning up from oversold
         else
            ok = (rsi[1] >= extreme_level_high && rsi[0] < rsi[1]); // turning down from overbought
      }
      IndicatorRelease(h);
      return ok;
   }

   //--------------------------------------------------------------------
   // H4 direction check – H4 candle must align with trade direction
   //--------------------------------------------------------------------
   bool H4DirectionCheck(string symbol, ENUM_POSITION_TYPE pos_type)
   {
      MqlRates h4[];
      ArraySetAsSeries(h4, true);
      if(CopyRates(symbol, PERIOD_H4, 1, 1, h4) < 1) return true; // allow if data unavailable
      if(pos_type == POSITION_TYPE_BUY)
         return (h4[0].close > h4[0].open);
      else
         return (h4[0].close < h4[0].open);
   }

   //--------------------------------------------------------------------
   // Initial entry signal – 15M 30-EMA cross or pull-back bounce
   //--------------------------------------------------------------------
   bool CheckInitialSignal(string symbol, ENUM_POSITION_TYPE &signal)
   {
      signal = WRONG_VALUE;

      int hEMA = iMA(symbol, PERIOD_M15, m_ema_period, 0, MODE_EMA, PRICE_CLOSE);
      if(hEMA == INVALID_HANDLE) return false;

      double ema[];
      ArraySetAsSeries(ema, true);
      if(CopyBuffer(hEMA, 0, 1, 2, ema) < 2) { IndicatorRelease(hEMA); return false; }
      IndicatorRelease(hEMA);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, PERIOD_M15, 1, 3, rates) < 3) return false;

      double close1 = rates[0].close, open1 = rates[0].open;
      double close2 = rates[1].close;
      double ema1   = ema[0], ema2 = ema[1];

      // Bullish: EMA cross-up or EMA bounce (strong bullish close above EMA)
      bool cross_up  = (close2 <= ema2 && close1 > ema1);
      bool bounce_up = (rates[0].low <= ema1 && close1 > ema1 && close1 > open1);
      if(cross_up || bounce_up) { signal = POSITION_TYPE_BUY;  return true; }

      // Bearish: EMA cross-down or EMA bounce (strong bearish close below EMA)
      bool cross_dn  = (close2 >= ema2 && close1 < ema1);
      bool bounce_dn = (rates[0].high >= ema1 && close1 < ema1 && close1 < open1);
      if(cross_dn || bounce_dn) { signal = POSITION_TYPE_SELL; return true; }

      return false;
   }

   //--------------------------------------------------------------------
   // Minimum adverse pip distance required before considering next level
   // (Expanded grid for v2 – distances increased at higher levels)
   //--------------------------------------------------------------------
   double GetRequiredLevelDistancePips(int next_level)
   {
      switch(next_level)
      {
         case 2: return  35.0;
         case 3: return  55.0;   // raised from 45
         case 4: return  80.0;   // raised from 65
         case 5: return 110.0;   // raised from 90
         case 6: return 150.0;   // raised from 125
         default: return 9999.0; // Level 7+ blocked (max 6)
      }
   }

   //--------------------------------------------------------------------
   // Reversal confirmation – conservative weighting increases with level
   //
   // PREREQUISITE for ALL levels: RSI must be in oversold/overbought zone.
   // Additional conditions tighten at each level.
   //--------------------------------------------------------------------
   bool CheckReversalConfirmation(string symbol, ENUM_POSITION_TYPE pos_type, int next_level)
   {
      // ── GATE: RSI prerequisite (applies to every martingale level) ──
      // BUY martingale: market must be oversold (RSI < 30)
      // SELL martingale: market must be overbought (RSI > 70)
      double rsi_m15 = GetRSI(symbol, PERIOD_M15, 1);
      bool rsi_extreme = (pos_type == POSITION_TYPE_BUY) ? (rsi_m15 < 30.0) : (rsi_m15 > 70.0);
      if(!rsi_extreme) return false;   // Prerequisite not met → block entry

      MqlRates m15[];
      ArraySetAsSeries(m15, true);
      if(CopyRates(symbol, PERIOD_M15, 1, 3, m15) < 3) return false;

      // ── Level 2: RSI oversold/overbought + single candlestick reversal ──
      if(next_level == 2)
      {
         // RSI prerequisite already passed (< 30 / > 70)
         // Candlestick: last closed bar must be in the trade direction
         if(pos_type == POSITION_TYPE_BUY)
            return (m15[0].close > m15[0].open);
         else
            return (m15[0].close < m15[0].open);
      }

      // ── Level 3: RSI extreme (≤ 25 / ≥ 75) + 2 consecutive M15 reversal bars ──
      if(next_level == 3)
      {
         bool rsi_deep = (pos_type == POSITION_TYPE_BUY) ? (rsi_m15 <= 25.0) : (rsi_m15 >= 75.0);
         if(!rsi_deep) return false;

         bool bar1_ok = (pos_type == POSITION_TYPE_BUY) ?
                        (m15[0].close > m15[0].open) : (m15[0].close < m15[0].open);
         bool bar2_ok = (pos_type == POSITION_TYPE_BUY) ?
                        (m15[1].close > m15[1].open) : (m15[1].close < m15[1].open);
         return (bar1_ok && bar2_ok);
      }

      // ── Level 4: RSI extreme + H1 candle reversal ──
      if(next_level == 4)
      {
         bool rsi_deep = (pos_type == POSITION_TYPE_BUY) ? (rsi_m15 <= 25.0) : (rsi_m15 >= 75.0);
         if(!rsi_deep) return false;

         MqlRates h1[];
         ArraySetAsSeries(h1, true);
         if(CopyRates(symbol, PERIOD_H1, 1, 1, h1) < 1) return false;
         if(pos_type == POSITION_TYPE_BUY)
            return (h1[0].close > h1[0].open);
         else
            return (h1[0].close < h1[0].open);
      }

      // ── Level 5: RSI extreme + 2 consecutive H1 reversal bars + H4 direction ──
      if(next_level == 5)
      {
         bool rsi_deep = (pos_type == POSITION_TYPE_BUY) ? (rsi_m15 <= 25.0) : (rsi_m15 >= 75.0);
         if(!rsi_deep) return false;

         MqlRates h1[];
         ArraySetAsSeries(h1, true);
         if(CopyRates(symbol, PERIOD_H1, 1, 2, h1) < 2) return false;

         bool h1bar1 = (pos_type == POSITION_TYPE_BUY) ?
                       (h1[0].close > h1[0].open) : (h1[0].close < h1[0].open);
         bool h1bar2 = (pos_type == POSITION_TYPE_BUY) ?
                       (h1[1].close > h1[1].open) : (h1[1].close < h1[1].open);
         if(!h1bar1 || !h1bar2) return false;

         return H4DirectionCheck(symbol, pos_type);
      }

      // ── Level 6: RSI ultra-extreme (≤ 20 / ≥ 80) + H1 + H4 full alignment ──
      if(next_level == 6)
      {
         double rsi_h1 = GetRSI(symbol, PERIOD_H1, 1);
         bool rsi_ultra_m15 = (pos_type == POSITION_TYPE_BUY) ? (rsi_m15 <= 20.0) : (rsi_m15 >= 80.0);
         bool rsi_h1_ext    = (pos_type == POSITION_TYPE_BUY) ? (rsi_h1  <= 30.0) : (rsi_h1  >= 70.0);
         if(!rsi_ultra_m15 || !rsi_h1_ext) return false;

         MqlRates h1[];
         ArraySetAsSeries(h1, true);
         if(CopyRates(symbol, PERIOD_H1, 1, 1, h1) < 1) return false;
         bool h1ok = (pos_type == POSITION_TYPE_BUY) ?
                     (h1[0].close > h1[0].open) : (h1[0].close < h1[0].open);
         if(!h1ok) return false;

         return H4DirectionCheck(symbol, pos_type);
      }

      return false; // Level 7+ is not allowed
   }

   //--------------------------------------------------------------------
   // Master check: Can we add the next martingale level?
   //--------------------------------------------------------------------
   bool CanAddMartingaleLevel(string symbol, const BasketInfo &basket,
                              int &next_level, string &reason)
   {
      next_level = basket.count + 1;
      if(next_level > 6)
      {
         reason = "Maximum martingale levels (6) reached. No further entries.";
         return false;
      }

      // 1. Adverse distance check (from the LAST open price in the basket)
      double req_pips = GetRequiredLevelDistancePips(next_level);
      double current  = (basket.pos_type == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(symbol, SYMBOL_BID) :
                         SymbolInfoDouble(symbol, SYMBOL_ASK);
      double adv_pips = (basket.pos_type == POSITION_TYPE_BUY) ?
                         PriceToPips(symbol, basket.last_open_price - current) :
                         PriceToPips(symbol, current - basket.last_open_price);

      if(adv_pips < req_pips)
      {
         reason = StringFormat("Adverse distance %.1f < required %.1f pips for L%d",
                               adv_pips, req_pips, next_level);
         return false;
      }

      // 2. Reversal confirmation (includes RSI prerequisite gate)
      if(!CheckReversalConfirmation(symbol, basket.pos_type, next_level))
      {
         reason = StringFormat("Distance OK (%.1f pips) – waiting for reversal confirmation (L%d)",
                               adv_pips, next_level);
         return false;
      }

      return true;
   }
};
