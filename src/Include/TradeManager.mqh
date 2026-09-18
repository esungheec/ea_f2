//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|                                  Copyright 2026, LEE Sunghee     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, LEE Sunghee"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

struct BasketInfo
{
   int                 count;
   double              total_lots;
   double              avg_price;
   ENUM_POSITION_TYPE  pos_type;
   double              total_profit;
   double              last_open_price;
   datetime            last_open_time;
   ulong               first_ticket;
   ulong               last_ticket;
};

class CTradeManager
{
private:
   CTrade            m_trade;
   CPositionInfo     m_position;
   CSymbolInfo       m_symbol_info;
   ulong             m_magic;

public:
   CTradeManager(ulong magic = 20260918)
   {
      m_magic = magic;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFillingBySymbol(_Symbol);
   }

   void SetMagicNumber(ulong magic)
   {
      m_magic = magic;
      m_trade.SetExpertMagicNumber(m_magic);
   }

   // Normalize volume based on symbol specifications
   double NormalizeVolume(string symbol, double volume)
   {
      if(!m_symbol_info.Name(symbol))
         return volume;
      m_symbol_info.Refresh();

      double min_lot  = m_symbol_info.LotsMin();
      double max_lot  = m_symbol_info.LotsMax();
      double step_lot = m_symbol_info.LotsStep();

      if(step_lot <= 0) step_lot = 0.01;
      double normalized = MathFloor(volume / step_lot) * step_lot;

      if(normalized < min_lot) normalized = min_lot;
      if(normalized > max_lot) normalized = max_lot;

      int digits = (int)MathMax(0, -MathLog10(step_lot));
      return NormalizeDouble(normalized, digits);
   }

   // Calculate martingale lot for a specific level (1.5x progression)
   double CalculateMartingaleLot(string symbol, double base_lot, int level)
   {
      if(level <= 1)
         return NormalizeVolume(symbol, base_lot);
      
      double lot = base_lot;
      for(int i = 1; i < level; i++)
      {
         lot = lot * 1.5;
      }
      return NormalizeVolume(symbol, lot);
   }

   // Retrieve basket statistics for a symbol
   bool GetBasketInfo(string symbol, BasketInfo &info)
   {
      ZeroMemory(info);
      info.pos_type = WRONG_VALUE;
      double weighted_sum = 0.0;

      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         if(!m_position.SelectByIndex(i))
            continue;

         if(m_position.Magic() == m_magic && m_position.Symbol() == symbol)
         {
            info.count++;
            double pos_vol = m_position.Volume();
            double pos_price = m_position.PriceOpen();
            info.total_lots += pos_vol;
            weighted_sum += (pos_price * pos_vol);
            info.total_profit += (m_position.Profit() + m_position.Swap());

            if(info.pos_type == WRONG_VALUE)
            {
               info.pos_type = m_position.PositionType();
               info.first_ticket = m_position.Ticket();
               info.last_ticket = m_position.Ticket();
               info.last_open_price = pos_price;
               info.last_open_time = (datetime)m_position.Time();
            }
            else
            {
               if((datetime)m_position.Time() > info.last_open_time)
               {
                  info.last_open_price = pos_price;
                  info.last_open_time = (datetime)m_position.Time();
                  info.last_ticket = m_position.Ticket();
               }
            }
         }
      }

      if(info.total_lots > 0)
      {
         info.avg_price = weighted_sum / info.total_lots;
         return true;
      }

      return false;
   }

   // Send market order
   bool OpenMarketOrder(string symbol, ENUM_POSITION_TYPE pos_type, double volume, double sl = 0.0, double tp = 0.0, string comment = "")
   {
      if(!m_symbol_info.Name(symbol))
         return false;
      m_symbol_info.RefreshRates();

      m_trade.SetTypeFillingBySymbol(symbol);
      double vol = NormalizeVolume(symbol, volume);

      if(pos_type == POSITION_TYPE_BUY)
      {
         double price = m_symbol_info.Ask();
         return m_trade.Buy(vol, symbol, price, sl, tp, comment);
      }
      else if(pos_type == POSITION_TYPE_SELL)
      {
         double price = m_symbol_info.Bid();
         return m_trade.Sell(vol, symbol, price, sl, tp, comment);
      }
      return false;
   }

   // Close all positions for a symbol under this magic number
   bool CloseBasket(string symbol)
   {
      bool all_closed = true;
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         if(!m_position.SelectByIndex(i))
            continue;

         if(m_position.Magic() == m_magic && m_position.Symbol() == symbol)
         {
            if(!m_trade.PositionClose(m_position.Ticket()))
            {
               all_closed = false;
               PrintFormat("Failed to close ticket #%I64u for %s, error: %d", m_position.Ticket(), symbol, GetLastError());
            }
         }
      }
      return all_closed;
   }
};
