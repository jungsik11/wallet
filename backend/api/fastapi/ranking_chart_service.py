"""
Service to fetch candlestick chart data for top-ranked stocks from the KIS API.
"""

import os
import time
from typing import Any, Dict, List

import requests
from utils import call_mcp_tool, MCP_STOCK_SERVER_URL

# --- Constants ---

KIS_URLS = {
    "prod": "https://openapi.koreainvestment.com:9443",
    "vps": "https://openapivts.koreainvestment.com:29443",
}

BASE_HEADERS = {
    "Content-Type": "application/json",
    "Accept": "text/plain",
    "charset": "UTF-8",
}
top_n: int = 10
# --- Internal Helper Functions ---


async def _get_top_ranked_stocks() -> List[Dict[str, Any]]:
    """Fetches the top rising stocks from major US exchanges."""
    unique_stocks_map: Dict[str, Dict[str, Any]] = {}

    for excd_val in ["NYS", "NAS", "AMS"]:
        params = {
            "excd": excd_val,
            "nday": "0",  # Today
            "gubn": "1",  # Rate of increase
            "vol_rang": "5",  # 1 million+ volume
            "keyb": "",
        }
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "updown_rate", params)

        if data and data.get('output2'):
            for item in data['output2']:
                try:
                    ticker = item.get('symb', '')
                    if ticker: # Only add if ticker is not empty
                        rate_val = float(item.get('rate', 0.0))
                        unique_stocks_map[ticker] = { # Use ticker as key to ensure uniqueness
                            "name": item.get('name', '이름 없음'),
                            "exch": item.get('excd', ''), 
                            "ticker": ticker,
                            "price": item.get('last', 0.0),
                            "diff": item.get('diff', 0.0),
                            "rate": rate_val,
                            "volume": item.get('tvol', 0),
                        }
                except (ValueError, TypeError):
                    continue # Skip if data is malformed
    
    all_stocks = list(unique_stocks_map.values())
    # Sort by rate of change in descending order and return
    return sorted(all_stocks, key=lambda x: x['rate'], reverse=True)[:top_n]


# --- Public Service Function ---

async def get_ranked_stocks() -> List[Dict[str, Any]]:
    """
    Fetches top N ranked stocks without their chart data for performance.

    Returns:
        A list of dictionaries, each containing stock info.
    """
    ranked_stocks = await _get_top_ranked_stocks()
    return ranked_stocks
