
"""
Runs the UptrendMomentumScreener algorithm periodically to generate real-time buy signals.
"""

import os
import sys
import time
from datetime import datetime
import pandas as pd

from dotenv import load_dotenv
from pykis import PyKis

# Add the project root to the Python path to allow for module imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from uptrend_momentum_screener import UptrendMomentumScreener
from trade_aggregator import TradeAggregator

# --- Configuration ---

RUN_INTERVAL_SECONDS = 60  # Run every 1 minute (60 seconds)

# --- Main Execution ---

if __name__ == '__main__':
    print("Starting Uptrend Momentum Screener Live Runner...")

    # Load environment variables from the project root .env file
    print("Loading environment variables...")
    load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))
    print("Environment variables loaded.")

    try:
        # Initialize KIS client
        print("Initializing PyKis client...")
        kis_client = PyKis(
            id=os.getenv("KIS_ID"),
            account=os.getenv("KIS_ACNT"),
            appkey=os.getenv("KIS_APPKEY"),
            secretkey=os.getenv("KIS_SECRET"),
            keep_token=True,
        )
        print("PyKis client initialized successfully.")

        # Initialize the screener algorithm
        print("Initializing UptrendMomentumScreener...")
        screener = UptrendMomentumScreener(kis_client=kis_client)
        print("UptrendMomentumScreener initialized.")

        # Initialize Trade Aggregator
        trade_aggregator = TradeAggregator()
        print("TradeAggregator initialized.")

        while True:
            current_time = pd.Timestamp.now(tz=screener.market_tz)

            # Check if within market hours for active screening
            if screener.market_open_time.date() == current_time.date() and \
               screener.market_open_time <= current_time <= screener.sell_window_end:
                print(f"\n--- Running screener at {current_time.strftime('%Y-%m-%d %H:%M:%S')} (Market Open) ---")
                try:
                    signals = screener.run()

                    if signals['buy_signals']:
                        print(f"\n--- Found {len(signals['buy_signals'])} NEW BUY SIGNALS! ---")
                        for signal in signals['buy_signals']:
                            print(signal)
                            trade_aggregator.record_buy(signal)
                    else:
                        print("No new buy signals found in this cycle.")

                    if signals['sell_signals']:
                        print(f"\n--- Found {len(signals['sell_signals'])} NEW SELL SIGNALS! ---")
                        for signal in signals['sell_signals']:
                            print(signal)
                            trade_aggregator.record_sell(signal)
                    else:
                        print("No new sell signals generated in this cycle.")

                    # Print trade summary
                    print("\n--- Current Trade Summary ---")
                    summary = trade_aggregator.get_summary()
                    for key, value in summary.items():
                        print(f"{key}: {value}")

                except Exception as e:
                    print(f"Error during screener run: {e}")

            else:
                print(f"\n--- Market Closed or Outside Trading Window ({current_time.strftime('%Y-%m-%d %H:%M:%S')}). Sleeping... ---")
            
            print(f"Sleeping for {RUN_INTERVAL_SECONDS} seconds until next cycle...")
            time.sleep(RUN_INTERVAL_SECONDS)

    except Exception as e:
        print(f"An error occurred during initialization: {e}")
