"""
Tests for the UptrendMomentumScreener algorithm.
"""

import pytest
from unittest.mock import MagicMock, patch
import pandas as pd
from datetime import datetime, timedelta
import pytz

from uptrend_momentum_screener import UptrendMomentumScreener

# --- Mock Data and Fixtures ---

@pytest.fixture
def mock_kis_client():
    """Creates a mock PyKis client."""
    client = MagicMock()
    client.token = "mock_token"
    client._appkey = "mock_appkey"
    client._secretkey = "mock_secretkey"
    return client

# Mock data for the top-ranked stocks API call
MOCK_RANKED_STOCKS_DATA = [
    # Should pass all filters and generate a buy signal
    {'ticker': 'PASS', 'name': 'Pass Inc.', 'price': 50.0, 'diff': 5.0, 'rate': 11.0},
    # Should fail the primary price filter
    {'ticker': 'FAIL_PRICE', 'name': 'Fail Price Ltd.', 'price': 0.5, 'diff': 2.0, 'rate': 200.0},
    # Should fail the primary price change filter
    {'ticker': 'FAIL_DIFF', 'name': 'Fail Diff Co.', 'price': 10.0, 'diff': 0.5, 'rate': 5.0},
    # Should pass primary, but fail daily trend analysis
    {'ticker': 'FAIL_DAILY', 'name': 'Fail Daily Trend', 'price': 20.0, 'diff': 2.0, 'rate': 10.0},
    # Should pass daily, but fail minute trend analysis
    {'ticker': 'FAIL_MINUTE', 'name': 'Fail Minute Trend', 'price': 30.0, 'diff': 3.0, 'rate': 10.0},
    # For sell test: initially uptrend, then downtrend
    {'ticker': 'SELL_TREND', 'name': 'Sell Trend Stock', 'price': 100.0, 'diff': 10.0, 'rate': 10.0},
    # For sell test: initially uptrend, then forced sell by time
    {'ticker': 'SELL_TIME', 'name': 'Sell Time Stock', 'price': 110.0, 'diff': 11.0, 'rate': 11.0},
]

# Mock chart data
MOCK_DATES = pd.date_range(start='2024-01-01', periods=60, freq='D')
MOCK_CHART_DATA = [
    {'date': date.strftime('%Y-%m-%d'), 'close': 100 + i, 'open': 99 + i, 'high': 102 + i, 'low': 98 + i, 'volume': 1000 + i * 10}
    for i, date in enumerate(MOCK_DATES)
]

# Mock minute chart data for sell tests
MOCK_MINUTE_CHART_UPTREND = [
    {'date': f'2024-01-01T09:30:00', 'close': 100, 'open': 99, 'high': 101, 'low': 98, 'volume': 100},
    {'date': f'2024-01-01T09:31:00', 'close': 101, 'open': 100, 'high': 102, 'low': 99, 'volume': 110},
    {'date': f'2024-01-01T09:32:00', 'close': 102, 'open': 101, 'high': 103, 'low': 100, 'volume': 120},
    # ... more data to ensure enough for trend analysis
] * 20 # Repeat to ensure enough data points for trend analysis

MOCK_MINUTE_CHART_DOWNTREND = [
    {'date': f'2024-01-01T09:30:00', 'close': 102, 'open': 103, 'high': 104, 'low': 101, 'volume': 100},
    {'date': f'2024-01-01T09:31:00', 'close': 101, 'open': 102, 'high': 103, 'low': 100, 'volume': 110},
    {'date': f'2024-01-01T09:32:00', 'close': 100, 'open': 101, 'high': 102, 'low': 99, 'volume': 120},
    # ... more data to ensure enough for trend analysis
] * 20 # Repeat to ensure enough data points for trend analysis


# --- Test Class ---

class TestUptrendMomentumScreener:

    @patch('uptrend_momentum_screener.UptrendMomentumScreener._fetch_top_ranked_stocks')
    @patch('uptrend_momentum_screener.UptrendMomentumScreener._fetch_chart_data')
    @patch('uptrend_momentum_screener.calculate_trend')
    @patch('pandas.Timestamp')
    def test_run_logic(self, mock_timestamp, mock_calculate_trend, mock_fetch_chart, mock_fetch_ranked, mock_kis_client):
        """
        Tests the entire run logic with various scenarios including buy/sell windows.
        """
        # --- Setup Mocks ---
        # Mock current time to be within the buy window
        market_tz = pytz.timezone('America/New_York')
        mock_now_buy_window = market_tz.localize(datetime(2024, 1, 1, 9, 45, 0)) # 15 mins after open
        mock_timestamp.now.return_value = MagicMock(wraps=mock_now_buy_window)

        mock_fetch_ranked.return_value = MOCK_RANKED_STOCKS_DATA

        # Configure chart data mock
        def chart_side_effect(ticker, timeframe):
            if ticker == 'SELL_TREND' and timeframe == 'M':
                return MOCK_MINUTE_CHART_DOWNTREND
            elif ticker == 'SELL_TIME' and timeframe == 'M':
                return MOCK_MINUTE_CHART_UPTREND # Initially uptrend
            return MOCK_CHART_DATA
        mock_fetch_chart.side_effect = chart_side_effect

        # Configure trend analysis mock
        def trend_side_effect(ohlcv_data, period, **kwargs):
            ticker = ohlcv_data[0].get('ticker', '')
            if ticker == 'FAIL_DAILY':
                return {'trend': 'Downtrend', 'normalized_slope': -0.1}
            if ticker == 'FAIL_MINUTE':
                return {'trend': 'Uptrend', 'normalized_slope': 0.1} if period == 30 else {'trend': 'Sideways', 'normalized_slope': 0.0}
            if ticker == 'SELL_TREND':
                return {'trend': 'Uptrend', 'normalized_slope': 0.1} if period == 30 else {'trend': 'Downtrend', 'normalized_slope': -0.1}
            if ticker == 'SELL_TIME':
                return {'trend': 'Uptrend', 'normalized_slope': 0.1}
            return {'trend': 'Uptrend', 'normalized_slope': 0.1}
        mock_calculate_trend.side_effect = trend_side_effect

        # --- Test 1: Buy window, no existing positions ---
        screener = UptrendMomentumScreener(kis_client=mock_kis_client)
        signals = screener.run()

        assert len(signals['buy_signals']) == 1
        assert signals['buy_signals'][0]['ticker'] == 'PASS'
        assert len(signals['sell_signals']) == 0
        assert screener.positions['PASS'] # Check that position is recorded

        # --- Test 2: Sell window, existing positions, trend reversal ---
        # Manually add a position for SELL_TREND
        screener.positions['SELL_TREND'] = {'name': 'Sell Trend Stock', 'buy_price': 100.0, 'buy_time': mock_now_buy_window}
        
        # Mock current time to be within sell window, but before 3-hour mark
        mock_now_sell_window = market_tz.localize(datetime(2024, 1, 1, 10, 0, 0)) # 30 mins after open
        mock_timestamp.now.return_value = mock_now_sell_window
        mock_timestamp.now.return_value.isoformat.return_value = mock_now_sell_window.isoformat()

        signals_sell_trend = screener.run()
        assert len(signals_sell_trend['buy_signals']) == 0 # No buy signals in this run
        assert len(signals_sell_trend['sell_signals']) == 1
        assert signals_sell_trend['sell_signals'][0]['ticker'] == 'SELL_TREND'
        assert signals_sell_trend['sell_signals'][0]['type'] == 'SELL'
        assert 'SELL_TREND' not in screener.positions # Check that position is removed

        # --- Test 3: Sell window, existing positions, forced sell by time ---
        # Manually add a position for SELL_TIME
        screener.positions['SELL_TIME'] = {'name': 'Sell Time Stock', 'buy_price': 110.0, 'buy_time': mock_now_buy_window}

        # Mock current time to be after 3-hour mark
        mock_now_forced_sell = market_tz.localize(datetime(2024, 1, 1, 12, 31, 0)) # 3 hours 1 min after open
        mock_timestamp.now.return_value = mock_now_forced_sell
        mock_timestamp.now.return_value.isoformat.return_value = mock_now_forced_sell.isoformat()

        signals_forced_sell = screener.run()
        assert len(signals_forced_sell['buy_signals']) == 0
        assert len(signals_forced_sell['sell_signals']) == 1
        assert signals_forced_sell['sell_signals'][0]['ticker'] == 'SELL_TIME'
        assert signals_forced_sell['sell_signals'][0]['type'] == 'SELL'
        assert 'Forced sell' in signals_forced_sell['sell_signals'][0]['reason']
        assert 'SELL_TIME' not in screener.positions

        # --- Test 4: Outside buy window ---
        mock_now_outside_buy_window = market_tz.localize(datetime(2024, 1, 1, 11, 31, 0)) # After buy window
        mock_timestamp.now.return_value = mock_now_outside_buy_window
        mock_timestamp.now.return_value.isoformat.return_value = mock_now_outside_buy_window.isoformat()

        signals_outside_buy = screener.run()
        assert len(signals_outside_buy['buy_signals']) == 0
        assert len(signals_outside_buy['sell_signals']) == 0 # No positions to sell


    @patch('uptrend_momentum_screener.UptrendMomentumScreener._fetch_top_ranked_stocks', return_value=[])
    def test_run_with_no_ranked_stocks(self, mock_fetch_ranked, mock_kis_client):
        """
        Tests the scenario where no ranked stocks are returned from the API.
        """
        screener = UptrendMomentumScreener(kis_client=mock_kis_client)
        signals = screener.run()

        assert len(signals['buy_signals']) == 0
        assert len(signals['sell_signals']) == 0