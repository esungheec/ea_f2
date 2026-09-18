import sys
import os
import json
import datetime
import subprocess
from typing import Dict, Any, List, Optional
import MetaTrader5 as mt5
from mcp.server.mcpserver import MCPServer

DEFAULT_TERMINAL_PATH = r"C:\Program Files\Eightcap Global MT5 Terminal_Test\terminal64.exe"
DEFAULT_METAEDITOR_PATH = r"C:\Program Files\Eightcap Global MT5 Terminal_Test\MetaEditor64.exe"

mcp = MCPServer(name="Eightcap_MT5_Assistant")

def _ensure_mt5() -> bool:
    if not mt5.initialize(path=DEFAULT_TERMINAL_PATH):
        return False
    return True

@mcp.tool()
def get_terminal_status() -> Dict[str, Any]:
    """Get MT5 terminal connection status, version, broker info and paths."""
    if not _ensure_mt5():
        return {"error": f"Failed to initialize MT5: {mt5.last_error()}"}
    
    t_info = mt5.terminal_info()
    version = mt5.version()
    if not t_info:
        return {"error": f"Failed to get terminal info: {mt5.last_error()}"}
    
    return {
        "connected": getattr(t_info, "connected", False),
        "trade_allowed": getattr(t_info, "trade_allowed", False),
        "name": getattr(t_info, "name", "Unknown"),
        "path": getattr(t_info, "path", ""),
        "data_path": getattr(t_info, "data_path", ""),
        "commondata_path": getattr(t_info, "commondata_path", ""),
        "version": version
    }

@mcp.tool()
def get_account_info() -> Dict[str, Any]:
    """Get connected MT5 trading account balance, equity, margin, leverage and server."""
    if not _ensure_mt5():
        return {"error": f"Failed to initialize MT5: {mt5.last_error()}"}
    
    acc = mt5.account_info()
    if not acc:
        return {"error": f"Failed to get account info: {mt5.last_error()}"}
    
    return {
        "login": acc.login,
        "server": acc.server,
        "currency": acc.currency,
        "balance": acc.balance,
        "equity": acc.equity,
        "profit": acc.profit,
        "margin": acc.margin,
        "margin_free": acc.margin_free,
        "margin_level": acc.margin_level,
        "leverage": acc.leverage,
        "trade_allowed": acc.trade_allowed,
        "name": acc.name
    }

@mcp.tool()
def get_symbols(search: str = "") -> List[str]:
    """List available trading symbols in MT5. Optionally filter by keyword (e.g. XAU, USD)."""
    if not _ensure_mt5():
        return []
    
    symbols = mt5.symbols_get()
    if not symbols:
        return []
    
    query = search.strip().upper()
    result = []
    for s in symbols:
        if not query or query in s.name.upper():
            result.append(s.name)
            if len(result) >= 100:
                break
    return result

@mcp.tool()
def get_symbol_info(symbol: str) -> Dict[str, Any]:
    """Get detailed market specification for a symbol (spread, bid/ask, point, digits, min lot)."""
    if not _ensure_mt5():
        return {"error": f"Failed to initialize MT5: {mt5.last_error()}"}
    
    # Ensure symbol is selected in Market Watch
    mt5.symbol_select(symbol, True)
    info = mt5.symbol_info(symbol)
    if not info:
        return {"error": f"Symbol '{symbol}' not found: {mt5.last_error()}"}
    
    return {
        "symbol": info.name,
        "bid": info.bid,
        "ask": info.ask,
        "spread": info.spread,
        "digits": info.digits,
        "point": info.point,
        "trade_contract_size": info.trade_contract_size,
        "volume_min": info.volume_min,
        "volume_max": info.volume_max,
        "volume_step": info.volume_step,
        "currency_base": info.currency_base,
        "currency_profit": info.currency_profit
    }

@mcp.tool()
def get_rates(symbol: str, timeframe: str = "M15", count: int = 50) -> Dict[str, Any]:
    """Get historical OHLCV candlestick bars for a symbol. Timeframe: M1, M5, M15, M30, H1, H4, D1."""
    if not _ensure_mt5():
        return {"error": f"Failed to initialize MT5: {mt5.last_error()}"}
    
    tf_map = {
        "M1": mt5.TIMEFRAME_M1,
        "M5": mt5.TIMEFRAME_M5,
        "M15": mt5.TIMEFRAME_M15,
        "M30": mt5.TIMEFRAME_M30,
        "H1": mt5.TIMEFRAME_H1,
        "H4": mt5.TIMEFRAME_H4,
        "D1": mt5.TIMEFRAME_D1,
        "W1": mt5.TIMEFRAME_W1,
        "MN1": mt5.TIMEFRAME_MN1,
    }
    
    tf = tf_map.get(timeframe.upper())
    if tf is None:
        return {"error": f"Invalid timeframe: {timeframe}. Allowed: {list(tf_map.keys())}"}
    
    mt5.symbol_select(symbol, True)
    rates = mt5.copy_rates_from_pos(symbol, tf, 0, min(count, 500))
    if rates is None or len(rates) == 0:
        return {"error": f"No rates found for {symbol} on {timeframe}: {mt5.last_error()}"}
    
    data = []
    for r in rates:
        dt = datetime.datetime.fromtimestamp(r["time"], tz=datetime.timezone.utc)
        data.append({
            "time": dt.strftime("%Y-%m-%d %H:%M:%S"),
            "open": float(r["open"]),
            "high": float(r["high"]),
            "low": float(r["low"]),
            "close": float(r["close"]),
            "tick_volume": int(r["tick_volume"]),
            "spread": int(r["spread"])
        })
    
    return {
        "symbol": symbol,
        "timeframe": timeframe.upper(),
        "count": len(data),
        "rates": data
    }

@mcp.tool()
def get_positions(symbol: str = "") -> List[Dict[str, Any]]:
    """Get list of current open trading positions. Optionally filter by symbol."""
    if not _ensure_mt5():
        return []
    
    if symbol:
        positions = mt5.positions_get(symbol=symbol)
    else:
        positions = mt5.positions_get()
        
    if positions is None:
        return []
    
    result = []
    for p in positions:
        result.append({
            "ticket": p.ticket,
            "symbol": p.symbol,
            "type": "BUY" if p.type == mt5.ORDER_TYPE_BUY else "SELL",
            "volume": p.volume,
            "price_open": p.price_open,
            "sl": p.sl,
            "tp": p.tp,
            "price_current": p.price_current,
            "profit": p.profit,
            "swap": p.swap,
            "comment": p.comment,
            "time": datetime.datetime.fromtimestamp(p.time, tz=datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        })
    return result

@mcp.tool()
def compile_mql5(source_file_path: str) -> Dict[str, Any]:
    """Compile an MQL5 file (.mq5) using MetaEditor64 and return compilation status and logs."""
    if not os.path.exists(source_file_path):
        return {"success": False, "error": f"Source file does not exist: {source_file_path}"}
    
    if not os.path.exists(DEFAULT_METAEDITOR_PATH):
        return {"success": False, "error": f"MetaEditor not found at: {DEFAULT_METAEDITOR_PATH}"}
    
    log_file = os.path.splitext(source_file_path)[0] + ".log"
    if os.path.exists(log_file):
        try:
            os.remove(log_file)
        except Exception:
            pass
            
    cmd = [DEFAULT_METAEDITOR_PATH, f"/compile:{source_file_path}", f"/log:{log_file}"]
    try:
        res = subprocess.run(cmd, capture_output=True, timeout=30)
    except Exception as e:
        return {"success": False, "error": f"Execution failed: {str(e)}"}
    
    log_content = ""
    if os.path.exists(log_file):
        for enc in ["utf-16", "utf-8", "cp1252", "euc-kr"]:
            try:
                with open(log_file, "r", encoding=enc) as f:
                    log_content = f.read()
                break
            except Exception:
                continue
    
    ex5_path = os.path.splitext(source_file_path)[0] + ".ex5"
    success = os.path.exists(ex5_path) and "0 errors" in log_content
    
    return {
        "success": success,
        "ex5_file": ex5_path if os.path.exists(ex5_path) else None,
        "log": log_content.strip() or "No log generated",
        "returncode": res.returncode
    }

if __name__ == "__main__":
    mcp.run(transport="stdio")
