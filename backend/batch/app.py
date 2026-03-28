import os
import requests
from pykis import KisChart, KisDailyOrders, PyKis
from dotenv import load_dotenv
from typing import Any, Dict, List

# Load environment variables
load_dotenv()

# KIS API configuration
KIS_URLS = {
    "prod": "https://openapi.koreainvestment.com:9443",
    "vps": "https://openapivts.koreainvestment.com:29443",
}

BASE_HEADERS = {
    "Content-Type": "application/json",
    "Accept": "text/plain",
    "charset": "UTF-8",
}

# Initialize PyKis client
try:
    kis = PyKis(
        id=os.getenv("KIS_ID"),
        account=os.getenv("KIS_ACNT"),
        appkey=os.getenv("KIS_APPKEY"),
        secretkey=os.getenv("KIS_SECRET"),
        keep_token=True,
    )
except Exception as e:
    print(f"Error initializing PyKis: {e}")
    kis = None

def _fetch_kis_api(
    kis: PyKis,
    api_url: str,
    tr_id: str,
    params: dict,
    svr: str = "prod", # Use prod for real data
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
        res.raise_for_status()
        return res.json()
    except requests.exceptions.RequestException as e:
        print(f"API request failed: {e}")
        if e.response:
            print(f"Response Text: {e.response.text}")
        return {}

def get_us_market_cap_ranking_over_500b():
    """
    Fetches US stocks with a market cap over $500 billion.
    """
    if not kis:
        print("KIS client not initialized.")
        return []

    api_url = "/uapi/overseas-stock/v1/ranking/updown-rate"
    tr_id = "HHDFS76350100"
    all_stocks = []
    
    # Market cap threshold: 500 billion USD.
    # The 'tomv' field from the API is in millions of USD.
    # So, 500 billion USD is 500,000 million USD.
    market_cap_threshold = 500000

    for excd_val in ["NYS", "NAS", "AMS"]:
        params = {"EXCD": excd_val}
        res = _fetch_kis_api(kis, api_url, tr_id, params)
        
        if res and res.get('output2'):
            etf_keywords = ["S&P 500", "NASDAQ", "NYSE", "MARKET", "ETF", "ETN", "INDEX", "FUND"]
            for item in res['output2']:
                stock_name = item.get('name', '').upper()
                
                is_etf = any(keyword in stock_name for keyword in etf_keywords)
                
                market_cap_million_usd = float(item.get('tomv', 0))

                if not is_etf and market_cap_million_usd > market_cap_threshold:
                    all_stocks.append({
                        "name": item.get('name', '이름 없음'),
                        "ticker": item.get('symb', ''),
                        "price": float(item.get('last', 0.0)),
                        "rate": float(item.get('rate', 0.0)),
                        "mcap": int(market_cap_million_usd * 1_000_000), # Store as full value
                    })

    # Sort by market cap in descending order
    sorted_stocks = sorted(all_stocks, key=lambda x: x['mcap'], reverse=True)
    return sorted_stocks

import pandas as pd
import numpy as np

def analyze_stock_with_kis(ticker: str, kis_client: PyKis) -> dict:
    """
    Analyzes a stock using KIS API data for 10-year uptrend, low daily volatility, 
    and negative latest change.

    Args:
        ticker: The stock ticker symbol (e.g., "AAPL").
        kis_client: An initialized PyKis client.

    Returns:
        A dictionary containing the analysis results.
    """
    try:
        # 1. Fetch up to 10 years of daily data using pykis
        stock = kis_client.stock(ticker)
        chart = stock.chart("10y")  # pykis handles fetching multi-year daily data

        if not chart or not chart.bars:
            return {"error": "Could not download stock chart data via KIS API."}

        # 2. Convert to pandas DataFrame
        df = pd.DataFrame([{
            'time': bar.time,
            'close': bar.close
        } for bar in chart.bars])

        # Convert close price from Decimal to float for calculations
        df['close'] = df['close'].astype(float)

        if len(df) < 252: # Require at least 1 year of data for meaningful analysis
            return {"error": f"Not enough data for analysis (found {len(df)} days)."}

        # 3. Check for long-term uptrend using linear regression (numpy.polyfit)
        # polyfit returns [slope, intercept]; we only need the slope.
        slope = np.polyfit(range(len(df)), df['close'], 1)[0]
        is_uptrend = slope > 0

        # 4. Check for low daily volatility
        daily_returns = df['close'].pct_change().dropna()
        volatility = daily_returns.std()
        # We define "low volatility" as less than 3% standard deviation
        is_low_volatility = volatility < 0.03

        # 5. Check if the latest day's change was negative
        latest_close = df['close'].iloc[-1]
        previous_close = df['close'].iloc[-2]
        is_negative_latest_change = (latest_close - previous_close) < 0

        return {
            "ticker": ticker,
            "10_year_uptrend": is_uptrend,
            "low_daily_volatility": is_low_volatility,
            "negative_latest_change": is_negative_latest_change,
            "data_points": len(df),
            "trend_slope": slope,
            "volatility_std_dev": volatility,
        }

    except Exception as e:
        return {"error": str(e)}


if __name__ == "__main__":
    if kis:
        # --- Example usage of the new analysis function ---
        ticker_to_analyze = "AAPL"  # Example: Apple Inc.
        print(f"\nAnalyzing {ticker_to_analyze} using KIS API...")
        analysis_result = analyze_stock_with_kis(ticker_to_analyze, kis)
        print(analysis_result)
        
        # You can test other tickers as well
        # print("\nAnalyzing MSFT...")
        # analysis_result_msft = analyze_stock_with_kis("MSFT", kis)
        # print(analysis_result_msft)

    print("\n" + "="*30 + "\n")
    
    # --- Keep the existing functionality ---
    top_stocks = get_us_market_cap_ranking_over_500b()
    if top_stocks:
        print("US Stocks with Market Cap over $500 Billion:")
        for stock in top_stocks:
            print(f"  - {stock['name']} ({stock['ticker']}): Market Cap: ${stock['mcap']:,}")
