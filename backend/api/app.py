"""
FastAPI application for providing stock and pension data from the Korea Investment & Securities (KIS) API.
"""

# --- Imports ---

import os
import time
import traceback
from datetime import datetime
from json import loads
from typing import Any, Dict, List

import pandas as pd
import requests
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from pykis import KisChart, KisDailyOrders, PyKis
from ranking_chart_service import get_charts_for_ranked_stocks

# --- FastAPI and KIS Initialization ---

# Load environment variables from .env file
load_dotenv()

# Initialize FastAPI app
app = FastAPI(title="Profit Calculation API")

# Initialize PyKis clients for both regular and pension accounts
try:
    kis = PyKis(
        id=os.getenv("KIS_ID"),
        account=os.getenv("KIS_ACNT"),
        appkey=os.getenv("KIS_APPKEY"),
        secretkey=os.getenv("KIS_SECRET"),
        keep_token=True,
    )
    pension_kis = PyKis(
        id=os.getenv("KIS_ID"),
        account=os.getenv("KIS_ACNT2"),
        appkey=os.getenv("KIS_APPKEY2"),
        secretkey=os.getenv("KIS_SECRET2"),
        keep_token=True,
    )

except Exception as e:
    print(f"Error initializing PyKis: {e}")
    # Exit or handle the error appropriately if KIS initialization fails
    # For now, we'll just print the error and continue
    kis = None
    pension_kis = None


# --- Pydantic Models ---

class ValuationProfitResponse(BaseModel):
    """Response model for valuation profit."""
    stocks: List[Dict[str, Dict[str, Any]]]

class StockHolding(BaseModel):
    """Model for individual stock holdings."""
    yearly_profit: Dict[str, float]
    holdings: Dict[str, Any]

class ProfitResponse(BaseModel):
    """Response model for overall profit calculation."""
    yearly_total_profit: Dict[str, float]
    stocks: List[Dict[str, StockHolding]]


# --- Internal Helper Functions ---

# Cache for get_history to avoid redundant API calls
_history_cache = {}
_history_cache_time = {}

# Caches for other API endpoints
_account_balance_cache = {}
_account_balance_cache_time = {}
_pension_balance_cache = {}
_pension_balance_cache_time = {}
_ohlcv_cache = {}
_ohlcv_cache_time = {}
_current_price_cache = {}
_current_price_cache_time = {}
_ranking_charts_cache = {}
_ranking_charts_cache_time = {}

CACHE_TTL = 60 * 5 # 5 minutes (adjust as needed)

# --- API Endpoints ---

@app.get("/valuation_profit", response_model=ValuationProfitResponse)
async def get_valuation_profit(country: str = Query("US", description="Country code (US or KR)")):
    """
    Calculates and returns the valuation profit for the holdings in the specified country.
    """
    try:
        order_set = _get_history(country, kis)
        df = pd.DataFrame(order_set).sort_values(by=['date', 'time'])
        
        if df.empty:
            return {'stocks': []}

        df_agg = df.groupby('ticker').agg({'quantity': 'sum', 'amount': 'sum', 'fee': 'sum'})
        df_agg = df_agg[df_agg['quantity'] != 0]
        df_agg = df_agg.astype({'quantity': 'float', 'amount': 'float'})
        df_agg['avg_price'] = (-(df_agg['amount'] + df_agg['fee']) / df_agg['quantity']).round(2)
        
        stocks_dict = loads(df_agg[['quantity', 'avg_price']].to_json(orient='index'))
        stocks = [{ticker: data} for ticker, data in stocks_dict.items()]

        return {'stocks': stocks}

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/calculate_profit", response_model=ProfitResponse)
async def calculate_profit(country: str = Query("US", description="Country code (US or KR)")):
    """
    Calculates the realized profit/loss for each stock and for each year using KIS account.profits().
    Includes a retry mechanism to handle connection errors.
    """
    max_retries = 3
    retry_delay = 1  # in seconds

    stocks_response = []

    for attempt in range(max_retries):
        try:
            if not kis:
                raise HTTPException(status_code=500, detail="KIS client not initialized.")

            profits_data = kis.account().profits(start=datetime(2021, 1, 1).date())

            yearly_total_profit = {}
            stock_yearly_profits = {}

            if profits_data and profits_data.orders:
                for order in profits_data.orders:
                    # Filter by country/market
                    if country == 'US' and order.market not in ['NASDAQ', 'NYSE', 'AMS']:
                        continue
                    if country == 'KR' and order.market != 'KRX':
                        continue

                    order_year = str(order.time_kst.year)
                    ticker = order.symbol
                    profit_amount = float(order.profit)

                    yearly_total_profit.setdefault(order_year, 0.0)
                    yearly_total_profit[order_year] += profit_amount

                    stock_yearly_profits.setdefault(ticker, {})
                    stock_yearly_profits[ticker].setdefault(order_year, 0.0)
                    stock_yearly_profits[ticker][order_year] += profit_amount

            stocks_response.clear()
            for ticker, yearly_data in stock_yearly_profits.items():
                stocks_response.append({
                    ticker: {
                        'yearly_profit': {year: round(p, 2) for year, p in yearly_data.items()},
                        'holdings': {} # No holding info from profits() API, so keep empty
                    }
                })

            final_response = {
                'yearly_total_profit': {year: round(p, 2) for year, p in yearly_total_profit.items()},
                'stocks': stocks_response
            }
            
            return final_response

        except requests.exceptions.ConnectionError as e:
            if attempt < max_retries - 1:
                print(f"Connection error in calculate_profit (attempt {attempt + 1}/{max_retries}): {e}. Retrying in {retry_delay}s...")
                time.sleep(retry_delay)
            else:
                print(f"Failed to calculate profit after {max_retries} attempts.")
                traceback.print_exc()
                raise HTTPException(status_code=500, detail=f"Failed to calculate profit: {e}")
        except Exception as e:
            traceback.print_exc()
            raise HTTPException(status_code=500, detail=str(e))


@app.get("/account_balance")
async def get_account_balance():
    """
    Fetches and returns the current account balance for the main account, including cash and stocks.
    Includes a retry mechanism to handle connection errors.
    """
    current_time = time.time()
    cache_key = "main_account_balance"

    if cache_key in _account_balance_cache and current_time - _account_balance_cache_time.get(cache_key, 0) < CACHE_TTL:
        return _account_balance_cache[cache_key]

    max_retries = 3
    retry_delay = 1  # in seconds

    for attempt in range(max_retries):
        try:
            if not kis:
                raise HTTPException(status_code=500, detail="KIS client not initialized.")
            
            balance = kis.account().balance()
            
            # Process cash balances
            krw_deposit = balance.deposits.get('KRW')
            usd_deposit = balance.deposits.get('USD')
            exchange_rate = usd_deposit.exchange_rate if usd_deposit and usd_deposit.exchange_rate else 1.0
            
            cash_response = {
                "krw": krw_deposit.amount if krw_deposit else 0,
                "usd": usd_deposit.amount if usd_deposit else 0,
                "usd_in_krw": round((usd_deposit.amount if usd_deposit else 0) * exchange_rate)
            }

            # Process stock balances
            stocks_response = []
            if balance.stocks:
                for stock in balance.stocks:
                    stock_data = {
                        "name": stock.name,
                        "ticker": stock.symbol,
                        "quantity": stock.qty,
                        "profit_loss_ratio": stock.profit_rate,
                        "market": stock.market,
                    }
                    if stock.market == 'KRX':
                        stock_data.update({
                            "average_price": round((stock.amount - stock.profit) / stock.qty, 2) if stock.qty > 0 else 0,
                            "current_price": stock.price,
                            "valuation": stock.amount,
                            "profit_loss": stock.profit,
                            "currency": "KRW"
                        })
                    else: # Overseas stocks
                        valuation_usd = stock.amount
                        profit_loss_usd = stock.profit
                        stock_data.update({
                            "average_price": round((valuation_usd - profit_loss_usd) / stock.qty, 2) if stock.qty > 0 else 0,
                            "current_price": round(stock.price, 2),
                            "valuation": round(valuation_usd * exchange_rate),
                            "valuation_usd": valuation_usd,
                            "profit_loss": round(profit_loss_usd * exchange_rate),
                            "profit_loss_usd": profit_loss_usd,
                            "currency": "USD"
                        })
                    stocks_response.append(stock_data)

            response_data = {
                "cash": cash_response,
                "stocks": stocks_response,
                "exchange_rate": exchange_rate
            }
            _account_balance_cache[cache_key] = response_data
            _account_balance_cache_time[cache_key] = current_time
            return response_data

        except requests.exceptions.ConnectionError as e:
            if attempt < max_retries - 1:
                print(f"Connection error in get_account_balance (attempt {attempt + 1}/{max_retries}): {e}. Retrying in {retry_delay}s...")
                time.sleep(retry_delay)
            else:
                print(f"Failed to fetch account balance after {max_retries} attempts.")
                traceback.print_exc()
                raise HTTPException(status_code=500, detail=f"Failed to fetch account balance: {e}")
        except Exception as e:
            traceback.print_exc()
            raise HTTPException(status_code=500, detail=str(e))


@app.get("/account_balance_pension")
async def get_account_balance_pension():
    """
    Fetches and returns the current account balance for the pension account.
    Includes a retry mechanism to handle connection errors.
    """
    max_retries = 3
    retry_delay = 1  # in seconds

    for attempt in range(max_retries):
        try:
            if not pension_kis:
                raise HTTPException(status_code=500, detail="Pension KIS client not initialized.")

            balance = pension_kis.account().balance()
            
            # Process cash balances
            krw_deposit = balance.deposits.get('KRW')
            usd_deposit = balance.deposits.get('USD')
            exchange_rate = usd_deposit.exchange_rate if usd_deposit and usd_deposit.exchange_rate else 1.0
            
            cash_response = {
                "krw": krw_deposit.amount if krw_deposit else 0,
                "usd": usd_deposit.amount if usd_deposit else 0,
                "usd_in_krw": round((usd_deposit.amount if usd_deposit else 0) * exchange_rate)
            }

            # Process stock balances
            stocks_response = []
            if balance.stocks:
                for stock in balance.stocks:
                    stock_data = {
                        "name": stock.name,
                        "ticker": stock.symbol,
                        "quantity": stock.qty,
                        "profit_loss_ratio": stock.profit_rate,
                        "market": stock.market,
                    }
                    if stock.market == 'KRX':
                        stock_data.update({
                            "average_price": round((stock.amount - stock.profit) / stock.qty, 2) if stock.qty > 0 else 0,
                            "current_price": stock.price,
                            "valuation": stock.amount,
                            "profit_loss": stock.profit,
                            "currency": "KRW"
                        })
                    else: # Overseas stocks
                        valuation_usd = stock.amount
                        profit_loss_usd = stock.profit
                        stock_data.update({
                            "average_price": round((valuation_usd - profit_loss_usd) / stock.qty, 2) if stock.qty > 0 else 0,
                            "current_price": round(stock.price, 2),
                            "valuation": round(valuation_usd * exchange_rate),
                            "valuation_usd": valuation_usd,
                            "profit_loss": round(profit_loss_usd * exchange_rate),
                            "profit_loss_usd": profit_loss_usd,
                            "currency": "USD"
                        })
                    stocks_response.append(stock_data)

            return {
                "cash": cash_response,
                "stocks": stocks_response,
                "exchange_rate": exchange_rate
            }

        except requests.exceptions.ConnectionError as e:
            if attempt < max_retries - 1:
                print(f"Connection error in get_account_balance_pension (attempt {attempt + 1}/{max_retries}): {e}. Retrying in {retry_delay}s...")
                time.sleep(retry_delay)
            else:
                print(f"Failed to fetch pension account balance after {max_retries} attempts.")
                traceback.print_exc()
                raise HTTPException(status_code=500, detail=f"Failed to fetch pension account balance: {e}")
        except Exception as e:
            traceback.print_exc()
            raise HTTPException(status_code=500, detail=str(e))


@app.get("/ohlcv")
async def get_ohlcv(ticker: str, timeframe: str = Query('D', description="Timeframe: 'D' (daily), 'W' (weekly), 'M' (monthly)")):
    """
    Fetches OHLCV (Open, High, Low, Close, Volume) data for a given ticker.
    """
    current_time = time.time()
    cache_key = f"ohlcv_{ticker}_{timeframe}"

    if cache_key in _ohlcv_cache and current_time - _ohlcv_cache_time.get(cache_key, 0) < CACHE_TTL:
        return _ohlcv_cache[cache_key]

    try:
        if not kis:
            raise HTTPException(status_code=500, detail="KIS client not initialized.")
            
        stock = kis.stock(ticker)
        if not stock:
            raise HTTPException(status_code=404, detail=f"Ticker {ticker} not found")
        
        chart = None
        if timeframe == 'D':
            chart = stock.chart("1y")
        elif timeframe == 'H':
            chart = stock.chart("5d", period=60)
        elif timeframe == 'M':
            chart = stock.chart("1d", period=1)
        else:
            raise HTTPException(status_code=400, detail=f"Invalid timeframe. Use 'D', 'H', or 'M'.")

        if not chart or not chart.bars:
            return {"market": stock.market, "data": []}

        ohlcv_data = [
            {
                "date": bar.time.isoformat(),
                "open": bar.open,
                "high": bar.high,
                "low": bar.low,
                "close": bar.close,
                "volume": bar.volume
            } for bar in chart.bars
        ]
        response_data = {"market": stock.market, "data": ohlcv_data}
        _ohlcv_cache[cache_key] = response_data
        _ohlcv_cache_time[cache_key] = current_time
        return response_data
    except Exception as e:
        print(f"Error getting ohlcv for {ticker}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/stock/detail")
async def get_stock_detail(ticker: str = Query(..., description="Stock ticker")):
    """
    Fetches detailed information for a given stock ticker.
    """
    current_time = time.time()
    cache_key = f"stock_detail_{ticker}"

    if cache_key in _current_price_cache and current_time - _current_price_cache_time.get(cache_key, 0) < CACHE_TTL:
        return _current_price_cache[cache_key]

    try:
        if not kis:
            raise HTTPException(status_code=500, detail="KIS client not initialized.")
        
        quote = kis.stock(ticker).quote()
        
        stock_data = {
            "name": kis.stock(ticker).name,
            "price": quote.price,
            "rate": quote.rate,
            "volume": quote.volume,
        }
        _current_price_cache[cache_key] = stock_data
        _current_price_cache_time[cache_key] = current_time
        return stock_data

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/ranking/charts")
async def get_ranking_charts(timeframe: str = Query('D', description="Timeframe: 'D' for daily, 'M' for 1-minute.")):
    """
    Fetches candlestick charts for the top 10 rising stocks.
    """
    try:
        if not kis:
            raise HTTPException(status_code=500, detail="KIS client not initialized.")
        
        chart_data = get_charts_for_ranked_stocks(kis, timeframe=timeframe)
        
        if not chart_data:
            return {"message": "No ranking data found or an error occurred."}
            
        return chart_data
        
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
