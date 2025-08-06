"""
Service to fetch candlestick chart data for top-ranked stocks from the KIS API.
"""

import os
from typing import Any, Dict, List

import requests
from pykis import PyKis

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

def _fetch_kis_api(
    kis: PyKis,
    api_url: str,
    tr_id: str,
    params: dict,
    svr: str = "vps",
) -> dict:
    """Generic function to fetch data from a KIS API endpoint."""
    token = kis.token
    if not token:
        raise ConnectionError("Failed to get a valid token from pykis.")

    headers = BASE_HEADERS.copy()
    headers["authorization"] = str(token)
    headers["appkey"] = kis._appkey
    headers["appsecret"] = kis._secretkey
    headers["tr_id"] = tr_id
    headers["custtype"] = "P"

    url = f"{KIS_URLS.get(svr)}{api_url}"

    try:
        res = requests.get(url, headers=headers, params=params)
        res.raise_for_status()  # Raise an exception for bad status codes (4xx or 5xx)
        return res.json()
    except requests.exceptions.RequestException as e:
        print(f"API request failed: {e}")
        print(f"Response Text: {e.response.text if e.response else 'No response'}")
        return {}


def _get_top_ranked_stocks(kis: PyKis) -> List[Dict[str, Any]]:
    """Fetches the top rising stocks from major US exchanges."""
    api_url = "/uapi/overseas-stock/v1/ranking/updown-rate"
    tr_id = "HHDFS76290000"
    all_stocks = []

    for excd_val in ["NYS", "NAS", "AMS"]:
        params = {
            "EXCD": excd_val,
            "NDAY": "0",  # Today
            "GUBN": "1",  # Rate of increase
            "VOL_RANG": "5",  # 1 million+ volume
            "KEYB": "",
        }
        res = _fetch_kis_api(kis, api_url, tr_id, params)

        if res and res.get('output2'):
            for item in res['output2'][:top_n]:
                try:
                    rate_val = float(item.get('rate', 0.0))
                    all_stocks.append({
                        "name": item.get('hnam', ''), # Changed from 'name' to 'hnam'
                        "exch": item.get('excd', ''), 
                        "ticker": item.get('symb', ''), # Changed from 'last' to 'symb'
                        "price": item.get('last', 0.0),
                        "diff": item.get('diff', 0.0),
                        "rate": rate_val,
                        "volume": item.get('tvol', 0),
                    })
                except (ValueError, TypeError):
                    continue # Skip if data is malformed
    
    # Sort by rate of change in descending order and return
    return sorted(all_stocks, key=lambda x: x['rate'], reverse=True)[:top_n]


# --- Public Service Function ---

def get_charts_for_ranked_stocks(
    kis: PyKis,
    timeframe: str = 'D',
    
) -> List[Dict[str, Any]]:
    """
    Fetches top N ranked stocks and their corresponding OHLCV chart data.

    Args:
        kis: An initialized PyKis client instance.
        timeframe: The chart timeframe, 'D' for daily or 'M' for 1-minute bars.
        top_n: The number of top stocks to fetch charts for.

    Returns:
        A list of dictionaries, each containing stock info and its chart data.
    """
    if not kis:
        raise ValueError("PyKis client is not initialized.")

    ranked_stocks = _get_top_ranked_stocks(kis)
    if not ranked_stocks:
        return []

    results = []
    for stock_info in ranked_stocks:
        ticker = stock_info.get('ticker')
        if not ticker:
            continue

        try:
            stock_obj = kis.stock(ticker) # Specify exchange

            if timeframe == 'D':
                chart = stock_obj.chart("1y")  # 1 year of daily data
            elif timeframe == 'M':
                chart = stock_obj.chart("1d", period=1)  # 1 day of 1-minute data
            else:
                print(f"Warning: Invalid timeframe '{timeframe}' for {ticker}. Skipping.")
                continue

            # Format chart data
            ohlcv_data = []
            if chart and chart.bars:
                for bar in chart.bars:
                    ohlcv_data.append({
                        "date": bar.time.isoformat(),
                        "open": bar.open,
                        "high": bar.high,
                        "low": bar.low,
                        "close": bar.close,
                        "volume": bar.volume,
                    })
            
            stock_info['chart_data'] = ohlcv_data
            results.append(stock_info)

        except Exception as e:
            print(f"Error fetching chart for {ticker}: {e}")
            # Add stock with empty chart data to indicate failure
            stock_info['chart_data'] = []
            results.append(stock_info)

    return results
