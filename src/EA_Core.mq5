//+------------------------------------------------------------------+
//|                                                      EA_Core.mq5 |
//|                                  Copyright 2026, LEE Sunghee     |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, LEE Sunghee"
#property link      "https://github.com/"
#property version   "1.00"
#property strict

//--- Inputs
input group "=== Trading Settings ==="
input double   InpLotSize          = 0.01;      // Fixed Lot Size
input int      InpStopLossPoints   = 150;       // Stop Loss (Points)
input int      InpTakeProfitPoints = 300;       // Take Profit (Points)
input ulong    InpMagicNumber      = 20260918;  // Magic Number

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("EA_Core initialized successfully on symbol: ", _Symbol);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA_Core deinitialized. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Strategy entry/exit logic will be placed here
  }
//+------------------------------------------------------------------+
