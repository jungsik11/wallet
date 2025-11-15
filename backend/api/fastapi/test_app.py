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

from app import app
from ranking_chart_service import get_ranked_stocks

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

# Mock for KIS API responses
class MockKisResponse:
    def __init__(self, content):
        self.content = [{'text': content}]

# --- Pytest Fixtures ---
@pytest.fixture
def mock_call_mcp_tool():
    """Mocks the app.call_mcp_tool function."""
    with patch('app.call_mcp_tool') as mock_func:
        yield mock_func



def test_calculate_profit_kr(mock_call_mcp_tool):
    """Tests the /calculate_profit endpoint for KR country with the final N+1 logic."""
    # Define the different mock responses for inquire_period_trade_profit
    mock_all_trades = {
        "output1": [
            {"prdt_name": "Samsung Electronics", "pdno": "005930"},
            {"prdt_name": "SK Hynix", "pdno": "000660"}
        ],
        "output2": [{"tot_rlzt_pfls": "75000"}] # Mock total profit in bulk call
    }
    mock_samsung_profit = {
        "output2": [{"rlzt_pfls_amt": "50000"}] # Per-stock profit
    }
    mock_hynix_profit = {
        "output2": [{"rlzt_pfls_amt": "25000"}] # Per-stock profit
    }

    # Create a side_effect function to return the correct mock based on input
    def mock_side_effect(mcp_server_url, tool_domain, api_type, params):
        pdno = params.get("pdno", "")
        if api_type == "inquire_period_trade_profit":
            if pdno == "":
                return mock_all_trades
            elif pdno == "005930":
                return mock_samsung_profit
            elif pdno == "000660":
                return mock_hynix_profit
        return {} # Default empty response

    mock_call_mcp_tool.side_effect = mock_side_effect

    response = client.get("/calculate_profit?country=KR&year=2023")
    assert response.status_code == 200
    data = response.json()

    assert 'yearly_total_profit' in data
    assert 'stocks' in data
    
    # Check total profit (now calculated from the sum of individual profits)
    assert data['yearly_total_profit']['KRW'] == pytest.approx(75000.0)
    
    # Check per-stock breakdown
    assert len(data['stocks']) == 2
    
    stock_profits = {s['holdings']['ticker']: s['yearly_profit']['KRW'] for s in data['stocks']}
    
    assert "005930" in stock_profits
    assert stock_profits["005930"] == pytest.approx(50000.0)
    
    assert "000660" in stock_profits
    assert stock_profits["000660"] == pytest.approx(25000.0)

def test_get_account_balance(mock_call_mcp_tool):
    """Tests the /account_balance endpoint."""
    # Mock the inquire_balance call for KR
    mock_call_mcp_tool.side_effect = [
        {"output1": [{"prdt_name": "Samsung Electronics", "pdno": "005930", "hldg_qty": "10", "evlu_pfls_rt": "6.67", "pchs_avg_pric": "75000", "prpr": "80000", "evlu_amt": "800000", "evlu_pfls_amt": "50000", "currency": "KRW"}], "output2": [{"dnca_tot_amt": "1000000"}]},
        # Mock the inquire_present_balance call for US
        {"output1": [{"prdt_name": "Apple Inc.", "pdno": "AAPL", "ccld_qty_smtl1": "5", "evlu_pfls_rt1": "20.0", "tr_mket_name": "NASD", "avg_unpr3": "150.0", "ovrs_now_pric1": "170.0", "frcr_evlu_amt2": "850.0", "evlu_pfls_amt2": "100.0", "buy_crcy_cd": "USD"}], "output2": [{"frcr_dncl_amt_2": "5000"}]}
    ]
    response = client.get("/account_balance?country=KR")
    assert response.status_code == 200
    data = response.json()
    assert 'cash' in data
    assert 'stocks' in data
    assert data['cash']['krw'] == 1000000
    assert len(data['stocks']) == 1
    assert data['stocks'][0]['ticker'] == '005930'

    response = client.get("/account_balance?country=US")
    assert response.status_code == 200
    data = response.json()
    assert 'cash' in data
    assert 'stocks' in data
    assert data['cash']['usd'] == 5000
    assert len(data['stocks']) == 1
    assert data['stocks'][0]['ticker'] == 'AAPL'

def test_get_account_balance_pension(mock_call_mcp_tool):
    """Tests the /account_balance_pension endpoint."""
    mock_call_mcp_tool.return_value = {"output1": [{"prdt_name": "Pension Stock", "pdno": "PENS", "hldg_qty": "10", "evlu_pfls_rt": "5.0", "pchs_avg_pric": "10000", "prpr": "10500", "evlu_amt": "105000", "evlu_pfls_amt": "5000", "currency": "KRW"}], "output2": [{"dnca_tot_amt": "500000"}]}
    response = client.get("/account_balance_pension")
    assert response.status_code == 200
    data = response.json()
    assert 'cash' in data
    assert 'stocks' in data
    assert data['cash']['krw'] == 500000
    assert len(data['stocks']) == 1

def test_get_ohlcv_overseas_no_exchange():
    """Tests the /ohlcv endpoint for overseas stock without exchange, expecting HTTPException."""
    response = client.get("/ohlcv?ticker=AAPL&timeframe=D")
    assert response.status_code == 400
    assert response.json()["detail"] == "Exchange code is required for overseas stocks."

def test_get_ohlcv_daily(mock_call_mcp_tool):
    """Tests the /ohlcv endpoint for daily timeframe."""
    mock_call_mcp_tool.return_value = {"output2": [{"stck_bsop_date": "20240102", "stck_oprc": "100", "stck_hgpr": "110", "stck_lwpr": "98", "stck_clpr": "105", "acml_vol": "10000"}, {"stck_bsop_date": "20240103", "stck_oprc": "105", "stck_hgpr": "115", "stck_lwpr": "103", "stck_clpr": "112", "acml_vol": "12000"}]}
    response = client.get("/ohlcv?ticker=005930&timeframe=D")
    assert response.status_code == 200
    data = response.json()
    assert 'data' in data
    assert len(data['data']) == 2
    assert data['data'][0]['open'] == 100

def test_get_ohlcv_weekly(mock_call_mcp_tool):
    """Tests the /ohlcv endpoint for weekly timeframe."""
    mock_call_mcp_tool.return_value = {"output2": [{"xymd": "20240105", "open": "100", "high": "115", "low": "98", "clos": "112", "tvol": "22000"}]}
    response = client.get("/ohlcv?ticker=AAPL&timeframe=W&exchange=NAS")
    assert response.status_code == 200
    data = response.json()
    assert 'data' in data
    assert len(data['data']) == 1 
    assert data['data'][0]['high'] == 115

def test_get_current_price(mock_call_mcp_tool):
    """Tests the /current_price/{ticker} endpoint."""
    mock_call_mcp_tool.return_value = [{"last": "175.5"}]
    response = client.get("/current_price/AAPL")
    assert response.status_code == 200
    data = response.json()
    assert 'current_price' in data
    assert data['current_price'] == 175.5

    mock_call_mcp_tool.return_value = [{"stck_prpr": "80000"}]
    response = client.get("/current_price/005930")
    assert response.status_code == 200
    data = response.json()
    assert 'current_price' in data
    assert data['current_price'] == 80000

def test_get_stock_detail(mock_call_mcp_tool):
    """Tests the /stock/{ticker} endpoint."""
    # Mock for overseas stock
    mock_call_mcp_tool.side_effect = [
        [{"last": "170.0", "diff": "5.0", "rate": "3.0", "tvol": "100000", "base": "165.0"}],
        {"output2": [{"xymd": "20240103", "open": "168.0", "high": "172.0", "low": "167.0", "clos": "170.0", "tvol": "100000"}]}
    ]
    response = client.get("/stock/AAPL?exchange=NAS")
    assert response.status_code == 200
    data = response.json()
    assert data['name'] == 'AAPL'
    assert data['price'] == 170.0
    assert data['high'] == 172.0

    # Mock for domestic stock
    mock_call_mcp_tool.side_effect = [
        [{"stck_prpr": "80000", "stck_prdy_diff": "1000", "prdy_ctrt": "1.27", "acml_vol": "1000000", "stck_oprc": "79500", "stck_hgpr": "80500", "stck_lwpr": "79000"}],
        {"prdt_name": "Samsung Electronics"}
    ]
    response = client.get("/stock/005930")
    assert response.status_code == 200
    data = response.json()
    assert data['name'] == 'Samsung Electronics'
    assert data['price'] == 80000
    assert data['high'] == 80500

def test_endpoint_not_found():
    """Tests a non-existent endpoint."""
    response = client.get("/non_existent_endpoint")
    assert response.status_code == 404


# --- Tests for Ranking Chart Service ---

MOCK_RANKED_STOCKS = [
    {'name': 'Stock A', 'ticker': 'STKA', 'rate': 25.5, 'price': 125.0, 'chart_data': [{'open': 100}, {'open': 101}]},
    {'name': 'Stock B', 'ticker': 'STKB', 'rate': 20.1, 'price': 50.0, 'chart_data': [{'open': 105}, {'open': 106}]},
]

@patch('app.get_ranked_stocks', return_value=MOCK_RANKED_STOCKS)
def test_get_ranking_charts_daily(mock_get_ranked):
    """Tests the /ranking/charts endpoint with daily timeframe."""
    response = client.get("/ranking/charts")
    assert response.status_code == 200
    data = response.json()
    
    assert len(data) == 2
    assert data[0]['ticker'] == 'STKA'
    assert 'chart_data' in data[0]
    assert len(data[0]['chart_data']) == 2
    assert data[0]['chart_data'][0]['open'] == 100

@patch('app.get_ranked_stocks', return_value=MOCK_RANKED_STOCKS)
def test_get_ranking_charts_minute(mock_get_ranked):
    """Tests the /ranking/charts endpoint with minute timeframe."""
    response = client.get("/ranking/charts?timeframe=M")
    assert response.status_code == 200
    data = response.json()

    assert len(data) == 2
    assert data[1]['ticker'] == 'STKB'
    assert len(data[1]['chart_data']) == 2