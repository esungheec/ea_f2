//+------------------------------------------------------------------+
//|                                                      EA_Core.mq5 |
//|                                  Copyright 2026, LEE Sunghee     |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, LEE Sunghee"
#property link      "https://github.com/"
#property version   "1.00"
#property strict

#include "Include\TradeManager.mqh"
#include "Include\ExposureGuard.mqh"
#include "Include\NewsFilter.mqh"
#include "Include\SignalEngine.mqh"

//--- Input Parameters
input group "=== 1. Account & Money Management ==="
input double   InpInitialLot              = 0.50;      // Base Lot Size ($100k account)
input double   InpMartingaleMultiplier    = 1.5;       // Martingale Multiplier (1.5x)
input int      InpMaxMartingaleLevels     = 8;         // Maximum Allowed Levels (Hard cap: 8)
input ulong    InpMagicNumber             = 20260918;  // EA Magic Number

input group "=== 2. Strategy Parameters ==="
input int      InpEMAPeriod               = 30;        // Baseline EMA Period (15M)
input double   InpMinTPPips               = 50.0;      // Minimum Target Profit (Pips)
input double   InpMaxTPPips               = 500.0;     // Maximum Target Profit (Pips)
input double   InpBasketProfitPips        = 35.0;      // Basket Exit Profit (Pips above Average Price)
input double   InpTrailingStartPips       = 50.0;      // Trailing Stop Activation (Level 1 only)
input double   InpTrailingStepPips        = 20.0;      // Trailing Step (Pips)

input group "=== 3. Exposure & Safety Guard ==="
input bool     InpUseNewsFilter           = true;      // Enable MT5 Economic Calendar Filter
input int      InpNewsWindowMinutes       = 60;        // News Blackout Window (+/- Minutes)
input int      InpMaxQuoteCurrencyBaskets = 3;         // Max Baskets per Quote Currency (JPY, NZD, SGD)
input int      InpMaxSpreadPoints         = 35;        // Maximum Allowed Spread (Points)

input group "=== 4. Multi-Currency Universe ==="
input bool     InpMultiCurrencyMode       = true;      // Master Multi-Currency Scanner
input string   InpSymbolsList             = "EURUSD.p,GBPUSD.p,USDJPY.p,USDCHF.p,USDCAD.p,AUDUSD.p,NZDUSD.p,EURGBP.p,EURJPY.p,EURCHF.p,EURAUD.p,EURCAD.p,EURNZD.p,EURSGD.p,GBPJPY.p,GBPCHF.p,GBPAUD.p,GBPCAD.p,GBPNZD.p,GBPSGD.p,AUDJPY.p,AUDCHF.p,AUDCAD.p,AUDNZD.p,AUDSGD.p,NZDJPY.p,NZDCHF.p,NZDCAD.p,NZDSGD.p,CADJPY.p,CADCHF.p,CHFJPY.p,SGDJPY.p,XAUUSD.p,USDSGD.p";

//--- Global Objects
CTradeManager  g_trade_manager(InpMagicNumber);
CExposureGuard g_exposure_guard;
CNewsFilter    g_news_filter(InpUseNewsFilter, InpNewsWindowMinutes);
CSignalEngine  g_signal_engine(InpEMAPeriod);

string         g_active_symbols[];
datetime       g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Helper to parse comma-separated symbol string                    |
//+------------------------------------------------------------------+
void ParseSymbols(string raw_list, string &symbols[])
{
   ArrayResize(symbols, 0);
   string temp[];
   int count = StringSplit(raw_list, StringGetCharacter(",", 0), temp);
   for(int i = 0; i < count; i++)
   {
      string sym = temp[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) > 0)
      {
         // Verify if symbol is available in terminal
         if(SymbolSelect(sym, true))
         {
            int sz = ArraySize(symbols);
            ArrayResize(symbols, sz + 1);
            symbols[sz] = sym;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update Chart Dashboard Display                                   |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int jpy_count = g_exposure_guard.CountActiveBasketsByQuote("JPY", InpMagicNumber);
   int nzd_count = g_exposure_guard.CountActiveBasketsByQuote("NZD", InpMagicNumber);
   int sgd_count = g_exposure_guard.CountActiveBasketsByQuote("SGD", InpMagicNumber);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin  = AccountInfoDouble(ACCOUNT_MARGIN);
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   string text = "";
   text += "====================================================\n";
   text += "  EA_F2: 15M 30-EMA Multi-Currency Martingale EA    \n";
   text += "====================================================\n";
   text += StringFormat(" Balance: $%.2f | Equity: $%.2f | Margin: $%.2f\n", balance, equity, margin);
   text += StringFormat(" Free Margin: $%.2f | Leverage: 1:%d\n", free_margin, (int)AccountInfoInteger(ACCOUNT_LEVERAGE));
   text += "----------------------------------------------------\n";
   text += StringFormat(" Active Tradable Pairs: %d symbols\n", ArraySize(g_active_symbols));
   text += StringFormat(" [Exposure Guard] JPY Baskets: %d / %d\n", jpy_count, InpMaxQuoteCurrencyBaskets);
   text += StringFormat(" [Exposure Guard] NZD Baskets: %d / %d\n", nzd_count, InpMaxQuoteCurrencyBaskets);
   text += StringFormat(" [Exposure Guard] SGD Baskets: %d / %d\n", sgd_count, InpMaxQuoteCurrencyBaskets);
   text += StringFormat(" [News Filter] %s (Window: +/- %d min)\n", InpUseNewsFilter ? "ACTIVE" : "OFF", InpNewsWindowMinutes);
   text += "====================================================\n";

   Comment(text);
}

//+------------------------------------------------------------------+
//| Process trading logic for a single symbol                        |
//+------------------------------------------------------------------+
void ProcessSymbol(string symbol)
{
   BasketInfo basket;
   bool has_basket = g_trade_manager.GetBasketInfo(symbol, basket);

   // --- CASE 1: Basket exists (Manage positions & Martingale) ---
   if(has_basket && basket.count > 0)
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double current_price = (basket.pos_type == POSITION_TYPE_BUY) ? bid : ask;

      double profit_pips = 0.0;
      if(basket.pos_type == POSITION_TYPE_BUY)
         profit_pips = g_signal_engine.PriceToPips(symbol, current_price - basket.avg_price);
      else
         profit_pips = g_signal_engine.PriceToPips(symbol, basket.avg_price - current_price);

      // --- EXIT CHECK ---
      if(basket.count == 1)
      {
         // Level 1: Dynamic TP (50 ~ 500 pips)
         double dynamic_tp = g_signal_engine.CalculateDynamicTPPips(symbol);
         if(profit_pips >= dynamic_tp)
         {
            PrintFormat("[%s] Level 1 Dynamic TP reached (%.1f / %.1f pips). Closing position.", symbol, profit_pips, dynamic_tp);
            g_trade_manager.CloseBasket(symbol);
            return;
         }
      }
      else // Levels 2 ~ 8
      {
         // Multi-level basket: Close on Average Break-even + Basket Profit Pips
         if(profit_pips >= InpBasketProfitPips)
         {
            PrintFormat("[%s] Basket Exit reached (%.1f pips profit above avg price for %d positions). Closing basket.", symbol, profit_pips, basket.count);
            g_trade_manager.CloseBasket(symbol);
            return;
         }
      }

      // --- ADDITIONAL MARTINGALE ENTRY CHECK (Levels 2 ~ 8) ---
      int next_level = 0;
      string reject_reason = "";
      if(g_signal_engine.CanAddMartingaleLevel(symbol, basket, next_level, reject_reason))
      {
         if(next_level <= InpMaxMartingaleLevels)
         {
            double next_lot = g_trade_manager.CalculateMartingaleLot(symbol, InpInitialLot, next_level);
            string comment = StringFormat("EA_F2_L%d", next_level);

            PrintFormat("[%s] Entering Martingale Level %d with %.2f lots. (Adverse distance reached + Reversal confirmed)", symbol, next_level, next_lot);
            g_trade_manager.OpenMarketOrder(symbol, basket.pos_type, next_lot, 0, 0, comment);
         }
      }
      return;
   }

   // --- CASE 2: No basket currently open -> Check for Level 1 Entry ---
   long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
      return; // Spread too wide

   // 1. Economic News Filter
   if(InpUseNewsFilter)
   {
      string news_title = "";
      datetime news_time = 0;
      if(g_news_filter.IsSymbolInNews(symbol, news_title, news_time))
      {
         // Skip entry during news window
         return;
      }
   }

   // 2. Exposure Guard (JPY, NZD, SGD limit)
   string reject_reason = "";
   if(!g_exposure_guard.CanOpenNewBasket(symbol, InpMagicNumber, InpMaxQuoteCurrencyBaskets, reject_reason))
   {
      return; // Quote currency limit reached
   }

   // 3. Technical Signal (15M 30-EMA)
   ENUM_POSITION_TYPE signal = WRONG_VALUE;
   if(g_signal_engine.CheckInitialSignal(symbol, signal))
   {
      double lot = g_trade_manager.NormalizeVolume(symbol, InpInitialLot);
      string comment = "EA_F2_L1";
      PrintFormat("[%s] Initial Level 1 Signal triggered: %s at %.2f lots", symbol, (signal == POSITION_TYPE_BUY ? "BUY" : "SELL"), lot);
      g_trade_manager.OpenMarketOrder(symbol, signal, lot, 0, 0, comment);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Initializing EA_F2 Multi-Currency Martingale System...");
   g_trade_manager.SetMagicNumber(InpMagicNumber);
   g_news_filter.SetEnabled(InpUseNewsFilter);
   g_news_filter.SetWindow(InpNewsWindowMinutes);

   if(InpMultiCurrencyMode)
   {
      ParseSymbols(InpSymbolsList, g_active_symbols);
      PrintFormat("Multi-currency mode active with %d tradable pairs.", ArraySize(g_active_symbols));
      EventSetTimer(3); // Scan symbols every 3 seconds
   }
   else
   {
      ArrayResize(g_active_symbols, 1);
      g_active_symbols[0] = _Symbol;
   }

   UpdateDashboard();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
   Print("EA_F2 deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ProcessSymbol(_Symbol);
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Timer event function for multi-symbol background scanning        |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpMultiCurrencyMode)
      return;

   for(int i = 0; i < ArraySize(g_active_symbols); i++)
   {
      ProcessSymbol(g_active_symbols[i]);
   }

   UpdateDashboard();
}
//+------------------------------------------------------------------+
