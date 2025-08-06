

import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch
from datetime import datetime
import os

# The app object must be imported AFTER setting the environment variables for the mock keys
os.environ["KIS_ID"] = "mock_id"
os.environ["KIS_ACNT"] = "mock_acnt"
os.environ["KIS_APPKEY"] = "mock_appkey"
os.environ["KIS_SECRET"] = "mock_secret"
os.environ["KIS_ACNT2"] = "mock_acnt2"
os.environ["KIS_APPKEY2"] = "mock_appkey2"
os.environ["KIS_SECRET2"] = "mock_secret2"

from app import app, kis, pension_kis
from ranking_chart_service import get_charts_for_ranked_stocks

client = TestClient(app)

# --- Mock Data ---

MOCK_ORDER_HISTORY = [
    {
        'date': '2023-01-15', 'time': '10:00:00', 'ticker': 'AAPL', 
        'order_type': 'buy', 'currency': 'USD', 'price': 150.0, 
        'quantity': 10.0, 'amount': -1500.0, 'fee': -3.75, 'exchange': 'NASD'
    },
    {
        'date': '2023-06-20', 'time': '14:30:00', 'ticker': 'AAPL', 
        'order_type': 'sell', 'currency': 'USD', 'price': 180.0, 
        'quantity': -5.0, 'amount': 900.0, 'fee': -2.25, 'exchange': 'NASD'
    },
    {
        'date': '2024-02-10', 'time': '11:00:00', 'ticker': 'TSLA', 
        'order_type': 'buy', 'currency': 'USD', 'price': 200.0, 
        'quantity': 5.0, 'amount': -1000.0, 'fee': -2.5, 'exchange': 'NASD'
    }
]

# Mock for pykis balance object
class MockDeposit:
    def __init__(self, amount, exchange_rate=1.0):
        self.amount = amount
        self.exchange_rate = exchange_rate

class MockStock:
    def __init__(self, name, symbol, qty, amount, profit, profit_rate, market, price, currency):
        self.name = name
        self.symbol = symbol
        self.qty = qty
        self.amount = amount
        self.profit = profit
        self.profit_rate = profit_rate
        self.market = market
        self.price = price
        self.currency = currency

class MockBalance:
    def __init__(self, deposits, stocks):
        self.deposits = deposits
        self.stocks = stocks

MOCK_BALANCE = MockBalance(
    deposits={'KRW': MockDeposit(1000000), 'USD': MockDeposit(5000, 1350.0)},
    stocks=[
        MockStock('Apple Inc.', 'AAPL', 5, 1125000, 225000, 20.0, 'NASD', 170.0, 'USD'),
        MockStock('Samsung Electronics', '005930', 10, 750000, 50000, 6.67, 'KRX', 80000, 'KRW')
    ]
)

# Mock for pykis chart object
class MockBar:
    def __init__(self, time, open, high, low, close, volume):
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    
    def model_dump(self):
        return {
            "time": self.time, "open": self.open, "high": self.high, 
            "low": self.low, "close": self.close, "volume": self.volume
        }

class MockChart:
    def __init__(self, bars):
        self.bars = bars

MOCK_CHART = MockChart(bars=[
    MockBar(datetime(2024, 1, 2), 100, 110, 98, 105, 10000),
    MockBar(datetime(2024, 1, 3), 105, 115, 103, 112, 12000)
])


# --- Pytest Fixtures ---

@pytest.fixture(autouse=True)
def mock_kis_clients():
    """Automatically mocks KIS clients for all tests."""
    with patch('app.kis', new=MagicMock()) as mock_kis, \
         patch('app.pension_kis', new=MagicMock()) as mock_pension_kis:
        
        # Mock account().balance()
        mock_kis.account().balance.return_value = MOCK_BALANCE
        mock_pension_kis.account().balance.return_value = MOCK_BALANCE
        
        # Mock stock().quote().price
        mock_kis.stock().quote.return_value = MagicMock(price=175.5)
        
        # Mock stock().chart()
        mock_kis.stock().chart.return_value = MOCK_CHART
        
        yield mock_kis, mock_pension_kis

@pytest.fixture
def mock_get_history():
    """Mocks the internal _get_history function."""
    with patch('app._get_history', return_value=MOCK_ORDER_HISTORY) as mock_func:
        yield mock_func


# --- Test Functions ---

def test_get_valuation_profit(mock_get_history):
    """Tests the /valuation_profit endpoint."""
    response = client.get("/valuation_profit?country=US")
    assert response.status_code == 200
    data = response.json()
    assert 'stocks' in data
    assert len(data['stocks']) == 2
    # Find AAPL stock and check its calculated average price
    aapl_stock = next((s['AAPL'] for s in data['stocks'] if 'AAPL' in s), None)
    assert aapl_stock is not None
    assert aapl_stock['avg_price'] == 121.2

def test_calculate_profit(mock_get_history):
    """Tests the /calculate_profit endpoint."""
    response = client.get("/calculate_profit?country=US")
    assert response.status_code == 200
    data = response.json()
    assert 'yearly_total_profit' in data
    assert 'stocks' in data
    assert '2023' in data['yearly_total_profit']
    assert data['yearly_total_profit']['2023'] == pytest.approx(145.88)

def test_get_account_balance():
    """Tests the /account_balance endpoint."""
    response = client.get("/account_balance")
    assert response.status_code == 200
    data = response.json()
    assert 'cash' in data
    assert 'stocks' in data
    assert data['cash']['krw'] == 1000000
    assert data['cash']['usd'] == 5000
    assert len(data['stocks']) == 2

def test_get_account_balance_pension():
    """Tests the /account_balance_pension endpoint."""
    response = client.get("/account_balance_pension")
    assert response.status_code == 200
    data = response.json()
    assert 'cash' in data
    assert 'stocks' in data
    assert data['cash']['usd'] == 5000
    assert len(data['stocks']) == 2

def test_get_ohlcv_daily():
    """Tests the /ohlcv endpoint for daily timeframe."""
    response = client.get("/ohlcv?ticker=AAPL&timeframe=D")
    assert response.status_code == 200
    data = response.json()
    assert 'data' in data
    assert len(data['data']) == 2
    assert data['data'][0]['open'] == 100

def test_get_ohlcv_weekly():
    """Tests the /ohlcv endpoint for weekly timeframe."""
    response = client.get("/ohlcv?ticker=AAPL&timeframe=W")
    assert response.status_code == 200
    data = response.json()
    assert 'data' in data
    # The mock data falls into the same week, so it should be resampled into one entry
    assert len(data['data']) == 1 
    assert data['data'][0]['high'] == 115 # Max high of the week

def test_get_current_price():
    """Tests the /current_price/{ticker} endpoint."""
    response = client.get("/current_price/AAPL")
    assert response.status_code == 200
    data = response.json()
    assert 'current_price' in data
    assert data['current_price'] == 175.5

def test_endpoint_not_found():
    """Tests a non-existent endpoint."""
    response = client.get("/non_existent_endpoint")
    assert response.status_code == 404


# --- Tests for Ranking Chart Service ---

MOCK_RANKED_STOCKS = [
    {'name': 'Stock A', 'ticker': 'STKA', 'rate': 25.5, 'price': 125.0},
    {'name': 'Stock B', 'ticker': 'STKB', 'rate': 20.1, 'price': 50.0},
]

@patch('ranking_chart_service._get_top_ranked_stocks', return_value=MOCK_RANKED_STOCKS)
@patch('pykis.PyKis.stock')
def test_get_ranking_charts_daily(mock_stock, mock_get_ranked):
    """Tests the /ranking/charts endpoint with daily timeframe."""
    # Mock the chart call for each stock
    mock_stock.return_value.chart.return_value = MOCK_CHART

    response = client.get("/ranking/charts?timeframe=D")
    assert response.status_code == 200
    data = response.json()
    
    assert len(data) == 2
    assert data[0]['ticker'] == 'STKA'
    assert 'chart_data' in data[0]
    assert len(data[0]['chart_data']) == 2
    assert data[0]['chart_data'][0]['open'] == 100

@patch('ranking_chart_service._get_top_ranked_stocks', return_value=MOCK_RANKED_STOCKS)
@patch('pykis.PyKis.stock')
def test_get_ranking_charts_minute(mock_stock, mock_get_ranked):
    """Tests the /ranking/charts endpoint with minute timeframe."""
    mock_stock.return_value.chart.return_value = MOCK_CHART

    response = client.get("/ranking/charts?timeframe=M")
    assert response.status_code == 200
    data = response.json()

    assert len(data) == 2
    assert data[1]['ticker'] == 'STKB'
    assert len(data[1]['chart_data']) == 2

