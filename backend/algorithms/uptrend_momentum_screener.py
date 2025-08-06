"""
Scans for momentum stocks that are in a confirmed uptrend on both daily and minute charts.
"""

import os
import sys
import time
from typing import Any, Dict, List
from datetime import datetime

# Add the project root to the Python path to allow for module imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
import pandas as pd
from dotenv import load_dotenv
from pykis import PyKis
import pytz

from functions.trend_analysis import calculate_trend

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

class UptrendMomentumScreener:
    """
    An algorithm that identifies buying opportunities by finding stocks that are:
    1. Among the top gainers.
    2. Meet minimum price and price change criteria.
    3. Are in a confirmed uptrend on both daily and minute charts.
    It also manages sell signals based on trend reversal or time limits.
    """

    def __init__(
        self, 
        kis_client: PyKis, 
        trend_period_daily: int = 30, 
        trend_period_minute: int = 60, 
        min_price: float = 1.0, 
        min_price_change: float = 1.0,
        market_open_hour: int = 9, # US market open hour (e.g., 9 for 9:30 AM EST)
        market_open_minute: int = 30,
        market_timezone: str = 'America/New_York' # EST
    ):
        """
        Initializes the screener.
        Args:
            kis_client: An initialized PyKis client.
            trend_period_daily: The lookback period for daily trend analysis.
            trend_period_minute: The lookback period for minute trend analysis.
            min_price: The minimum current price for a stock to be considered.
            min_price_change: The minimum price change for a stock to be considered.
            market_open_hour: Hour of market open in market_timezone.
            market_open_minute: Minute of market open in market_timezone.
            market_timezone: Timezone string for the market (e.g., 'America/New_York').
        """
        if not kis_client:
            raise ValueError("A valid PyKis client must be provided.")
        
        self.kis = kis_client
        self.trend_period_daily = trend_period_daily
        self.trend_period_minute = trend_period_minute
        self.min_price = min_price
        self.min_price_change = min_price_change
        self.name = "Uptrend Momentum Screener"

        self.market_tz = pytz.timezone(market_timezone)
        # Create a naive datetime object for market open time, then localize it
        self.market_open_time = self.market_tz.localize(datetime.now().replace(
            hour=market_open_hour, minute=market_open_minute, second=0, microsecond=0
        ))
        self.buy_window_end = self.market_open_time + pd.Timedelta(minutes=90) # 1.5 hours after open
        self.sell_window_end = self.market_open_time + pd.Timedelta(hours=3) # 3 hours after open

        self.positions = {} # To keep track of currently held positions: {ticker: {buy_price, buy_time}}

    def _fetch_top_ranked_stocks(self) -> List[Dict[str, Any]]:
        """Fetches the top rising stocks from major US exchanges via KIS API."""
        api_url = "/uapi/overseas-stock/v1/ranking/updown-rate"
        tr_id = "HHDFS76290000"
        all_stocks = []

        headers = BASE_HEADERS.copy()
        headers["authorization"] = str(self.kis.token)
        headers["appkey"] = os.getenv("KIS_APPKEY")
        headers["appsecret"] = os.getenv("KIS_SECRET")
        headers["tr_id"] = tr_id
        headers["custtype"] = "P"

        for excd_val in ["NYS", "NAS", "AMS"]:
            params = {"EXCD": excd_val, "NDAY": "0", "GUBN": "1", "VOL_RANG": "4"}
            url = f"{KIS_URLS.get('vps')}{api_url}"
            try:
                res = requests.get(url, headers=headers, params=params)
                res.raise_for_status()
                data = res.json()
                time.sleep(0.1) # Add a small delay after each API call

                for item in data['output2'][:10]:
                    all_stocks.append({
                        'name': item.get('hnam', ''),
                        'ticker': item.get('symb', ''),
                        'price': float(item.get('last', 0.0)),
                        'diff': float(item.get('diff', 0.0)),
                        'rate': float(item.get('rate', 0.0)),
                    })
            except requests.exceptions.RequestException as e:
                print(f"Error fetching ranking for {excd_val}: {e}")
                continue
        
        return sorted(all_stocks, key=lambda x: x['rate'], reverse=True)[:10]

    def _fetch_chart_data(self, ticker: str, timeframe: str, retries: int = 3, delay: float = 0.5) -> List[Dict[str, Any]]:
        """
        Fetches OHLCV data for a given ticker and timeframe with retry mechanism.
        Returns data in a format suitable for trend analysis.
        """
        for attempt in range(retries):
            try:
                stock_obj = self.kis.stock(ticker)
                if timeframe == 'D':
                    chart = stock_obj.chart("3m")  # 3 months of daily data
                elif timeframe == 'M':
                    chart = stock_obj.chart("1d", period=1)  # 1 day of 1-minute data
                else:
                    print(f"Invalid timeframe '{timeframe}' for {ticker}. Returning empty.")
                    return []

                if not chart or not chart.bars:
                    print(f"No chart data or bars for {ticker} ({timeframe}) on attempt {attempt + 1}.")
                    if attempt < retries - 1:
                        time.sleep(delay)
                        continue
                    return []
                
                # Ensure 'date' and 'close' are present and correctly formatted
                formatted_data = []
                for bar in chart.bars:
                    formatted_data.append({
                        'date': bar.time.isoformat(), # Use isoformat for consistency
                        'close': bar.close,
                        'open': bar.open,
                        'high': bar.high,
                        'low': bar.low,
                        'volume': bar.volume
                    })
                time.sleep(delay) # Add a small delay after successful fetch
                return formatted_data
            except Exception as e:
                print(f"Error fetching chart for {ticker} ({timeframe}) on attempt {attempt + 1}: {e}")
                if attempt < retries - 1:
                    time.sleep(delay)
                else:
                    return []
        return [] # Should not be reached

    def run(self) -> Dict[str, List[Dict[str, Any]]]:
        """
        Runs the entire screening and analysis process, generating buy and sell signals.
        """
        print(f"--- Running {self.name} ---")
        current_time = pd.Timestamp.now(tz=self.market_tz)
        buy_signals = []
        sell_signals = []

        # --- Sell Logic (for existing positions) ---
        for ticker, position_info in list(self.positions.items()): # Iterate over a copy
            print(f"\nChecking existing position for {ticker}...")
            
            # Check if 3 hours from market open has passed
            if current_time >= self.sell_window_end:
                print(f"  Market close window reached for {ticker}. Forcing sell.")
                minute_chart = self._fetch_chart_data(ticker, 'M')
                if minute_chart:
                    sell_price = minute_chart[-1]['close'] # Use last close price for forced sell
                    sell_signals.append({
                        'ticker': ticker,
                        'name': position_info['name'],
                        'price': sell_price,
                        'signal_time': current_time.isoformat(),
                        'type': 'SELL',
                        'reason': "Forced sell: 3-hour market window expired.",
                        'buy_price': position_info['buy_price'] # Add buy_price here
                    })
                    del self.positions[ticker]
                continue

            # Analyze minute trend for existing positions
            minute_chart = self._fetch_chart_data(ticker, 'M')
            if not minute_chart:
                print(f"  Could not fetch minute chart for {ticker}. Skipping sell analysis.")
                continue

            minute_trend_result = calculate_trend(minute_chart, period=self.trend_period_minute)
            print(f"  - Minute Trend for {ticker}: {minute_trend_result['trend']} (Slope: {minute_trend_result['normalized_slope']})")

            # Generate sell signal if minute trend turns downtrend/sideways
            if minute_trend_result['trend'] != 'Uptrend':
                sell_price = minute_chart[-1]['close'] # Use last close price for sell
                sell_signals.append({
                    'ticker': ticker,
                    'name': position_info['name'],
                    'price': sell_price,
                    'signal_time': current_time.isoformat(),
                    'type': 'SELL',
                    'reason': f"Trend reversal: Minute chart turned {minute_trend_result['trend']}.",
                    'buy_price': position_info['buy_price'] # Add buy_price here
                })
                del self.positions[ticker]

        # --- Buy Logic ---
        # Only consider buying within the first 1.5 hours of market open
        if current_time < self.market_open_time or current_time > self.buy_window_end:
            print("Not within buy window. Skipping buy signal generation.")
            return {'buy_signals': buy_signals, 'sell_signals': sell_signals}

        ranked_stocks = self._fetch_top_ranked_stocks()
        print(f"Found {len(ranked_stocks)} top-gaining stocks. Now filtering for buy signals...")

        for stock in ranked_stocks:
            # Skip if already holding this stock
            if stock['ticker'] in self.positions:
                print(f"  Already holding {stock['ticker']}. Skipping buy analysis.")
                continue

            # 1. Apply primary filters
            if not (stock['price'] >= self.min_price and stock['diff'] >= self.min_price_change):
                continue

            print(f"\nChecking {stock['ticker']} (Price: ${stock['price']:.2f}, Change: ${stock['diff']:.2f})...")

            # Analyze daily trend
            daily_chart = self._fetch_chart_data(stock['ticker'], 'D')
            if not daily_chart:
                continue
            
            daily_trend_result = calculate_trend(daily_chart, period=self.trend_period_daily)
            # Ensure 'normalized_slope' exists before accessing
            daily_slope = daily_trend_result.get('normalized_slope', 0.0)
            print(f"  - Daily Trend: {daily_trend_result['trend']} (Slope: {daily_slope})")

            if daily_trend_result['trend'] == 'Uptrend':
                # 3. Analyze minute trend if daily is an uptrend
                minute_chart = self._fetch_chart_data(stock['ticker'], 'M')
                if not minute_chart:
                    continue

                minute_trend_result = calculate_trend(minute_chart, period=self.trend_period_minute)
                # Ensure 'normalized_slope' exists before accessing
                minute_slope = minute_trend_result.get('normalized_slope', 0.0)
                print(f"  - Minute Trend: {minute_trend_result['trend']} (Slope: {minute_slope})")

                # 4. Generate buy signal if both are uptrends
                if minute_trend_result['trend'] == 'Uptrend':
                    signal = {
                        'ticker': stock['ticker'],
                        'name': stock['name'],
                        'price': stock['price'],
                        'signal_time': current_time.isoformat(),
                        'type': 'BUY',
                        'reason': f"Confirmed uptrend on Daily (slope: {daily_trend_result['normalized_slope']}) and Minute (slope: {minute_trend_result['normalized_slope']}) charts."
                    }
                    buy_signals.append(signal)
                    self.positions[stock['ticker']] = {'name': stock['name'], 'buy_price': stock['price'], 'buy_time': current_time}
                    print(f"  >> BUY SIGNAL GENERATED FOR {stock['ticker']}!")
        
        print(f"\n--- Screening Complete. Found {len(buy_signals)} buy signals and {len(sell_signals)} sell signals. ---")
        return {'buy_signals': buy_signals, 'sell_signals': sell_signals}

# --- Main execution block to run the algorithm as a standalone script ---
if __name__ == '__main__':
    load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))

    try:
        # Initialize KIS client
        kis_client = PyKis(
            id=os.getenv("KIS_ID"),
            account=os.getenv("KIS_ACNT"),
            appkey=os.getenv("KIS_APPKEY"),
            secretkey=os.getenv("KIS_SECRET"),
            keep_token=True,
        )

        # Initialize and run the screener
        # For testing market hours, you might need to adjust market_open_hour/minute
        # or mock pd.Timestamp.now() in a test environment.
        screener = UptrendMomentumScreener(kis_client=kis_client)
        signals = screener.run()

        # Print final results
        if signals['buy_signals']:
            print("\n--- Final Buy Signals ---")
            for signal in signals['buy_signals']:
                print(signal)
        else:
            print("\nNo stocks met all the criteria for a buy signal.")

        if signals['sell_signals']:
            print("\n--- Final Sell Signals ---")
            for signal in signals['sell_signals']:
                print(signal)
        else:
            print("\nNo sell signals generated.")

    except Exception as e:
        print(f"An error occurred during the main execution: {e}")
