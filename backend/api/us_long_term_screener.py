import os
import time
from typing import Any, Dict, List

import requests
from pykis import PyKis

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
    headers["appkey"] = os.getenv("KIS_APPKEY")
    headers["appsecret"] = os.getenv("KIS_SECRET")
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


def get_us_long_term_stocks(kis: PyKis) -> List[Dict[str, Any]]:
    """Fetches the top rising stocks from major US exchanges."""
    api_url = "/uapi/overseas-stock/v1/ranking/updown-rate"
    tr_id = "HHDFS76350100"
    all_stocks = []

    for excd_val in ["NYS", "NAS", "AMS"]:
        params = {
            "EXCD": excd_val,
        }
        res = _fetch_kis_api(kis, api_url, tr_id, params)
        if res and res.get('output2'):
            etf_keywords = ["S&P 500", "NASDAQ", "NYSE", "MARKET", "ETF", "ETN", "INDEX", "FUND"]
            for item in res['output2']:
                stock_name = item.get('name', '').upper()
                
                is_etf = False
                for keyword in etf_keywords:
                    if keyword in stock_name:
                        is_etf = True
                        break
                
                if not is_etf and float(item.get('tomv', 0)) > 5*10**11:
                    all_stocks.append({
                        "name": item.get('name', '이름 없음'),
                        "ticker": item.get('symb', ''),
                        "price": float(item.get('last', 0.0)),
                        "rate": float(item.get('rate', 0.0)),
                        "mcap": int(item.get('tomv', 0)),
                    })
    # Sort by rate of change in descending order and return
    return sorted(all_stocks, key=lambda x: x['mcap'], reverse=True)

