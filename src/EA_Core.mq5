//+------------------------------------------------------------------+
//|                                                      EA_Core.mq5 |
//|                                  Copyright 2026, LEE Sunghee     |
//|                                  https://github.com/esungheec/   |
//+------------------------------------------------------------------+
//  v2.0 – Basket exit on net USD profit; max martingale 6 levels;
//          Exposure guard: all quote currencies limited to 4 baskets;
//          34 target currency pairs.
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, LEE Sunghee"
#property link      "https://github.com/esungheec/ea_f2"
#property version   "2.00"
#property strict

#include "Include\TradeManager.mqh"
#include "Include\ExposureGuard.mqh"
#include "Include\NewsFilter.mqh"
#include "Include\SignalEngine.mqh"

//--- Input Parameters
input group "=== 1. Account & Money Management ==="
input double   InpInitialLot              = 0.50;      // Base Lot Size
input double   InpMartingaleMultiplier    = 1.5;       // Martingale Multiplier (1.5x per level)
input int      InpMaxMartingaleLevels     = 6;         // Maximum Martingale Levels (hard cap: 6)
input double   InpBasketTargetUSD        = 25.0;       // Basket Net Profit Target (USD) – used when basket has 2+ positions
input ulong    InpMagicNumber             = 20260918;  // EA Magic Number

input group "=== 2. Strategy Parameters ==="
input int      InpEMAPeriod               = 30;        // Baseline EMA Period (15M)
input double   InpMinTPPips               = 50.0;      // Minimum TP for single position (Pips)
input double   InpMaxTPPips               = 500.0;     // Maximum TP for single position (Pips)

input group "=== 3. Exposure & Safety Guard ==="
input bool     InpUseNewsFilter           = true;      // Enable MT5 Economic Calendar Filter
input int      InpNewsWindowMinutes       = 60;        // News Blackout Window (+/- Minutes)
input int      InpMaxQuoteCurrencyBaskets = 4;         // Max Baskets per Quote Currency (all pairs)
input int      InpMaxSpreadPoints         = 35;        // Maximum Allowed Spread (Points)

input group "=== 4. Multi-Currency Universe ==="
input bool     InpMultiCurrencyMode       = true;      // Master Multi-Currency Scanner
// 34 target pairs – add broker suffix (e.g. .p) if required
input string   InpSymbolsList = "GBPAUD,EURNZD,GBPJPY,AUDJPY,USDJPY,EURJPY,GBPSGD,EURAUD,AUDUSD,"
                                "CHFJPY,GBPNZD,EURUSD,NZDUSD,GBPUSD,NZDJPY,GBPCAD,GBPCHF,SGDJPY,"
                                "AUDSGD,CADJPY,AUDCAD,NZDCAD,USDCHF,AUDNZD,EURCAD,AUDCHF,USDCAD,"
                                "USDSGD,NZDSGD,CADCHF,EURSGD,NZDCHF,EURGBP,EURCHF";

//--- Global Objects
CTradeManager  g_trade_manager(InpMagicNumber);
CExposureGuard g_exposure_guard;
CNewsFilter    g_news_filter(InpUseNewsFilter, InpNewsWindowMinutes);
CSignalEngine  g_signal_engine(InpEMAPeriod);

string         g_active_symbols[];

//+------------------------------------------------------------------+
//| Parse comma-separated symbol string; auto-detect broker suffix   |
//+------------------------------------------------------------------+
void ParseSymbols(string raw_list, string &symbols[])
{
   ArrayResize(symbols, 0);
   string temp[];
   int count = StringSplit(raw_list, StringGetCharacter(",", 0), temp);

   // Common broker suffixes to try when bare symbol is not available
   string suffixes[] = {"", ".p", ".m", ".a", "_", ".pro"};

   for(int i = 0; i < count; i++)
   {
      string sym = temp[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) == 0) continue;

      bool added = false;
      for(int s = 0; s < ArraySize(suffixes); s++)
      {
         string candidate = sym + suffixes[s];
         if(SymbolSelect(candidate, true))
         {
            // Verify it actually exists (has a valid bid price)
            if(SymbolInfoDouble(candidate, SYMBOL_BID) > 0)
            {
               int sz = ArraySize(symbols);
               ArrayResize(symbols, sz + 1);
               symbols[sz] = candidate;
               added = true;
               break;
            }
         }
      }
      if(!added)
         PrintFormat("[ParseSymbols] Symbol '%s' not found in terminal (tried all suffixes). Skipped.", sym);
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double free_margin= AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   // Count active baskets per notable quote currency for display
   string display_quotes[] = {"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF","SGD"};
   string quote_status = "";
   for(int q = 0; q < ArraySize(display_quotes); q++)
   {
      int cnt = g_exposure_guard.CountActiveBasketsByQuote(display_quotes[q], InpMagicNumber);
      if(cnt > 0)
         quote_status += StringFormat("  %s: %d/%d\n", display_quotes[q], cnt, InpMaxQuoteCurrencyBaskets);
   }

   string text = "";
   text += "=====================================================\n";
   text += "  EA_F2 v2.0 – 15M 30-EMA Multi-Currency Martingale \n";
   text += "=====================================================\n";
   text += StringFormat(" Balance: $%.2f | Equity: $%.2f | Free Margin: $%.2f\n", balance, equity, free_margin);
   text += StringFormat(" Leverage: 1:%d | Active Pairs: %d\n",
                        (int)AccountInfoInteger(ACCOUNT_LEVERAGE), ArraySize(g_active_symbols));
   text += "-----------------------------------------------------\n";
   text += StringFormat(" [Strategy] Initial Lot: %.2f | Max Martingale Levels: %d\n",
                        InpInitialLot, InpMaxMartingaleLevels);
   text += StringFormat(" [Basket Exit] Net Target: $%.2f per basket\n", InpBasketTargetUSD);
   text += StringFormat(" [Exposure Guard] Max per quote currency: %d baskets\n", InpMaxQuoteCurrencyBaskets);
   text += " [Quote Exposure]\n" + (StringLen(quote_status) > 0 ? quote_status : "  (none)\n");
   text += StringFormat(" [News Filter] %s (Window: +/-%d min)\n",
                        InpUseNewsFilter ? "ACTIVE" : "OFF", InpNewsWindowMinutes);
   text += "=====================================================\n";

   Comment(text);
}

//+------------------------------------------------------------------+
//| Core processing logic per symbol                                  |
//+------------------------------------------------------------------+
void ProcessSymbol(string symbol)
{
   BasketInfo basket;
   bool has_basket = g_trade_manager.GetBasketInfo(symbol, basket);

   // ── CASE 1: Basket exists – manage existing positions ──
   if(has_basket && basket.count > 0)
   {
      // ── EXIT CHECK ──
      if(basket.count == 1)
      {
         //  Single position: use dynamic ATR-based TP (50–500 pip)
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         double current_price = (basket.pos_type == POSITION_TYPE_BUY) ? bid : ask;

         double profit_pips = (basket.pos_type == POSITION_TYPE_BUY)
            ? g_signal_engine.PriceToPips(symbol, current_price - basket.avg_price)
            : g_signal_engine.PriceToPips(symbol, basket.avg_price - current_price);

         double dynamic_tp = g_signal_engine.CalculateDynamicTPPips(symbol);
         if(profit_pips >= dynamic_tp)
         {
            PrintFormat("[%s] L1 Dynamic TP hit (%.1f / %.1f pips). Closing position.",
                        symbol, profit_pips, dynamic_tp);
            g_trade_manager.CloseBasket(symbol);
            return;
         }
      }
      else
      {
         // Martingale basket (2+ positions):
         // Exit condition: total NET profit of ALL positions >= InpBasketTargetUSD
         // Individual positions do not need to be profitable – risk management priority.
         if(basket.total_profit >= InpBasketTargetUSD)
         {
            PrintFormat("[%s] Basket net profit $%.2f >= target $%.2f (%d positions). Closing basket.",
                        symbol, basket.total_profit, InpBasketTargetUSD, basket.count);
            g_trade_manager.CloseBasket(symbol);
            return;
         }
      }

      // ── MARTINGALE ADD CHECK ──
      int    next_level   = 0;
      string reject_reason = "";
      if(g_signal_engine.CanAddMartingaleLevel(symbol, basket, next_level, reject_reason))
      {
         if(next_level <= InpMaxMartingaleLevels)
         {
            double next_lot = g_trade_manager.CalculateMartingaleLot(symbol, InpInitialLot, next_level);
            string comment  = StringFormat("EA_F2_L%d", next_level);
            PrintFormat("[%s] Martingale L%d: %.2f lots (RSI-confirmed reversal + distance met).",
                        symbol, next_level, next_lot);
            g_trade_manager.OpenMarketOrder(symbol, basket.pos_type, next_lot, 0, 0, comment);
         }
      }
      return;
   }

   // ── CASE 2: No basket open – check for Level 1 entry ──

   // Spread filter
   long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints) return;

   // News filter
   if(InpUseNewsFilter)
   {
      string news_title = ""; datetime news_time = 0;
      if(g_news_filter.IsSymbolInNews(symbol, news_title, news_time)) return;
   }

   // Exposure guard – all quote currencies limited to InpMaxQuoteCurrencyBaskets
   string reject_reason = "";
   if(!g_exposure_guard.CanOpenNewBasket(symbol, InpMagicNumber, InpMaxQuoteCurrencyBaskets, reject_reason))
   {
      // Silently skip; dashboard already shows current counts
      return;
   }

   // Technical signal (15M 30-EMA cross / bounce)
   ENUM_POSITION_TYPE signal = WRONG_VALUE;
   if(g_signal_engine.CheckInitialSignal(symbol, signal))
   {
      double lot     = g_trade_manager.NormalizeVolume(symbol, InpInitialLot);
      string comment = "EA_F2_L1";
      PrintFormat("[%s] L1 Signal: %s at %.2f lots",
                  symbol, (signal == POSITION_TYPE_BUY ? "BUY" : "SELL"), lot);
      g_trade_manager.OpenMarketOrder(symbol, signal, lot, 0, 0, comment);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Initializing EA_F2 v2.0 Multi-Currency Martingale System...");
   g_trade_manager.SetMagicNumber(InpMagicNumber);
   g_news_filter.SetEnabled(InpUseNewsFilter);
   g_news_filter.SetWindow(InpNewsWindowMinutes);

   if(InpMultiCurrencyMode)
   {
      ParseSymbols(InpSymbolsList, g_active_symbols);
      PrintFormat("Multi-currency mode: %d tradable pairs loaded.", ArraySize(g_active_symbols));
      EventSetTimer(3);
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
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
   Print("EA_F2 v2.0 deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| OnTick – processes the chart's own symbol                         |
//+------------------------------------------------------------------+
void OnTick()
{
   ProcessSymbol(_Symbol);
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| OnTimer – scans all symbols in multi-currency mode               |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpMultiCurrencyMode) return;

   for(int i = 0; i < ArraySize(g_active_symbols); i++)
      ProcessSymbol(g_active_symbols[i]);

   UpdateDashboard();
}
//+------------------------------------------------------------------+
