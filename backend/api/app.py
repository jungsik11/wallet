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
    print(f"KIS Token: {kis.token}")
    print(f"Pension KIS Token: {pension_kis.token}")
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

def _get_history(country: str, client: PyKis) -> List[Dict[str, Any]]:
    """
    Fetches and processes the daily order history for a given country using the specified KIS client.
    Implements a simple in-memory cache to reduce API calls.
    """
    current_time = time.time()
    cache_key = f"{client.account()}-{country}"

    # Check cache first
    if cache_key in _history_cache and current_time - _history_cache_time.get(cache_key, 0) < 60:
        return _history_cache[cache_key]

    if not client:
        raise HTTPException(status_code=500, detail="KIS client not initialized.")

    # Get account and daily orders
    account = client.account()
    daily_orders: KisDailyOrders = account.daily_orders(
        start=datetime.strptime('2021-01-01', '%Y-%m-%d').date(),
        end=datetime.today().date(),
        country=country
    )

    # Process orders into a standardized format
    order_set = []
    for order in daily_orders.orders:
        if order.executed_qty != 0:
            amount = order.price * order.executed_qty
            quantity = order.executed_qty
            if order.type == 'sell':
                quantity = -quantity
            else:
                amount = -amount

            order_data = {
                'date': order.time.strftime('%Y-%m-%d'),
                'time': order.time.strftime('%H:%M:%S'),
                'ticker': order.symbol,
                'order_type': order.type,
                'currency': order.currency,
                'price': float(order.price),
                'quantity': float(quantity),
                'amount': float(amount),
                'fee': float(order.executed_amount) * -0.0025
            }
            if hasattr(order, 'exchange'):
                order_data['exchange'] = order.exchange
            order_set.append(order_data)

    # Update cache
    _history_cache[cache_key] = order_set
    _history_cache_time[cache_key] = current_time

    return order_set


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
    Calculates the realized profit/loss for each stock and for each year using FIFO method.
    """
    try:
        order_set = _get_history(country, kis)
        df = pd.DataFrame(order_set).sort_values(by=['date', 'time'])
        df['date'] = pd.to_datetime(df['date'])

        if df.empty:
            return {'yearly_total_profit': {}, 'stocks': []}

        tickers = df['ticker'].unique()
        yearly_total_profit = {}
        stocks_response = []

        for tic in tickers:
            stock_yearly_profit = {}
            dft = df[df['ticker'] == tic].copy()
            holdings_queue = []  # FIFO queue for buy orders

            for _, row in dft.iterrows():
                if row.order_type == 'buy':
                    holdings_queue.append({'price': row.price, 'quantity': row.quantity})
                elif row.order_type == 'sell':
                    sell_year = str(row.date.year)
                    sell_price = row.price
                    quantity_to_sell = abs(row.quantity)
                    
                    yearly_total_profit.setdefault(sell_year, 0)
                    stock_yearly_profit.setdefault(sell_year, 0)

                    while quantity_to_sell > 0 and holdings_queue:
                        buy_order = holdings_queue[0]
                        match_quantity = min(quantity_to_sell, buy_order['quantity'])
                        
                        profit = (sell_price * match_quantity * 0.9975) - (buy_order['price'] * match_quantity * 1.0025)
                        
                        yearly_total_profit[sell_year] += profit
                        stock_yearly_profit[sell_year] += profit
                        
                        quantity_to_sell -= match_quantity
                        buy_order['quantity'] -= match_quantity
                        
                        if buy_order['quantity'] < 1e-9:
                            holdings_queue.pop(0)
            
            # Calculate remaining holdings
            total_quantity = sum(h['quantity'] for h in holdings_queue)
            total_cost = sum(h['price'] * h['quantity'] for h in holdings_queue)
            avg_price = round(total_cost / total_quantity, 2) if total_quantity > 0 else 0

            stock_holdings = {
                'detail': [(h['price'], h['quantity']) for h in holdings_queue if h['quantity'] > 1e-9],
                'total': total_quantity,
                'avg_price': avg_price,
                'exchange': dft.iloc[0].get('exchange', 'NASD' if country == 'US' else '')
            }

            stocks_response.append({
                tic: {
                    'yearly_profit': {year: round(p, 2) for year, p in stock_yearly_profit.items()},
                    'holdings': stock_holdings
                }
            })

        final_response = {
            'yearly_total_profit': {year: round(p, 2) for year, p in yearly_total_profit.items()},
            'stocks': stocks_response
        }
        
        return final_response

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/account_balance")
async def get_account_balance():
    """
    Fetches and returns the current account balance for the main account, including cash and stocks.
    """
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

        return {
            "cash": cash_response,
            "stocks": stocks_response,
            "exchange_rate": exchange_rate
        }

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/account_balance_pension")
async def get_account_balance_pension():
    """
    Fetches and returns the current account balance for the pension account.
    """
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

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/ohlcv")
async def get_ohlcv(ticker: str, timeframe: str = Query('D', description="Timeframe: 'D' (daily), 'W' (weekly), 'M' (monthly)")):
    """
    Fetches OHLCV (Open, High, Low, Close, Volume) data for a given ticker.
    """
    try:
        if not kis:
            raise HTTPException(status_code=500, detail="KIS client not initialized.")
            
        stock = kis.stock(ticker)
        if not stock:
            raise HTTPException(status_code=404, detail=f"Ticker {ticker} not found")

        # Determine chart parameters based on timeframe
        if timeframe == 'D':
            chart = stock.chart("1y")
        elif timeframe == 'W':
            chart = stock.chart("5y")
        elif timeframe == 'M':
            chart = stock.chart("10y")
        else:
            raise HTTPException(status_code=400, detail="Invalid timeframe. Use 'D', 'W', or 'M'.")

        if not chart or not chart.bars:
            return {"market": stock.market, "data": []}

        # Unified data processing path
        df = pd.DataFrame([bar.model_dump() for bar in chart.bars])
        df['time'] = pd.to_datetime(df['time'])
        df.set_index('time', inplace=True)

        if timeframe in ['W', 'M']:
            resample_period = 'W-MON' if timeframe == 'W' else 'M'
            ohlc_dict = {'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last', 'volume': 'sum'}
            df = df.resample(resample_period, label='left').agg(ohlc_dict).dropna()
        
        df.reset_index(inplace=True)
        df.rename(columns={'time': 'date'}, inplace=True)
        df['date'] = pd.to_datetime(df['date']).dt.strftime('%Y-%m-%d')
        
        # Ensure correct data types for serialization
        df[['open', 'high', 'low', 'close']] = df[['open', 'high', 'low', 'close']].astype(float)
        df['volume'] = df['volume'].astype(int)

        ohlcv_data = df[['date', 'open', 'high', 'low', 'close', 'volume']].to_dict(orient='records')

        return {"market": stock.market, "data": ohlcv_data}
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/current_price/{ticker}")
async def get_current_price(ticker: str):
    """
    Fetches the current price for a given stock ticker.
    """
    try:
        if not kis:
            raise HTTPException(status_code=500, detail="KIS client not initialized.")
        price = kis.stock(ticker).quote().price
        return {"current_price": price}
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error fetching price for {ticker}: {e}")


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
