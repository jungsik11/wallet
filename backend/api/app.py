from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from datetime import datetime, date
import pandas as pd
from json import loads, dumps
import os, copy
from decimal import Decimal
from dotenv import load_dotenv
from pykis import PyKis, KisDailyOrders, KisChart
from fastapi.responses import JSONResponse
from datetime import datetime, timedelta
import time

# Initialize FastAPI
app = FastAPI(title="Profit Calculation API")

# Initialize PyKis client
print(f"KIS_ID: {os.getenv('KIS_ID')}")
print(f"KIS_ACNT: {os.getenv('KIS_ACNT')}")
print(f"KIS_APPKEY: {os.getenv('KIS_APPKEY')}")
print(f"KIS_SECRET: {os.getenv('KIS_SECRET')}")
kis = PyKis(
    id=os.getenv("KIS_ID"),
    account=os.getenv("KIS_ACNT"),
    appkey=os.getenv("KIS_APPKEY"),
    secretkey=os.getenv("KIS_SECRET"),
    keep_token=True,
)

# Define models
class DateRange(BaseModel):
    start_date: str
    end_date: str
    country: str = "US"

class OrderDetail(BaseModel):
    date: str
    time: str
    ticker: str
    order_type: str
    currency: str
    price: float
    quantity: float
    amount: float
    fee: float

class StockHolding(BaseModel):
    yearly_profit: Dict[str, float]
    holdings: Dict[str, Any]

class ProfitResponse(BaseModel):
    yearly_total_profit: Dict[str, float]
    stocks: List[Dict[str, StockHolding]]


class ValuationProfitResponse(BaseModel):
    stocks: List[Dict[str, Dict[str, Any]]]

    

# Cache for get_history
history_cache = {}
history_cache_time = {}

def get_history(country):
    # Check cache
    current_time = time.time()
    if country in history_cache and current_time - history_cache_time.get(country, 0) < 60:
        return history_cache[country]
        
    # Get account
    account = kis.account()

    # Get daily orders
    daily_orders: KisDailyOrders = account.daily_orders(
        start=datetime.strptime('2021-01-01', '%Y-%m-%d').date(),
        end=datetime.today().date(),#datetime.strptime(datetime.today.date(), '%Y-%m-%d').date(), 
        country=country
    )

    # Process orders
    order_set = []
    for order in daily_orders.orders:
        if order.executed_qty != 0:
            a = order.price * order.executed_qty
            q = order.executed_qty
            if order.type == 'sell': 
                q = -q
            else:
                a = -a
            o = {
                'date': order.time.strftime('%Y-%m-%d'),
                'time': order.time.strftime('%H:%M:%S'),
                'ticker': order.symbol,
                'order_type': order.type,
                'currency': order.currency,
                'price': float(order.price),
                'quantity': float(q),
                'amount': float(a),
                'fee': float(order.executed_amount) * -0.0025
            }
            if hasattr(order, 'exchange'):
                o['exchange'] = order.exchange
            order_set.append(o)
            
    # Update cache
    history_cache[country] = order_set
    history_cache_time[country] = current_time

    return order_set

@app.get("/valuation_profit", response_model=ValuationProfitResponse)
async def valuation_profit(
    country: str = Query("US", description="Country code")
):
    try:
        order_set = get_history(country)
        # Convert to DataFrame
        df = pd.DataFrame(order_set).sort_values(by=['date', 'time'])
        df1 = df.groupby('ticker').agg( {'quantity': 'sum', 'amount': 'sum', 'fee': 'sum'})
        df1 = df1.query('quantity != 0')
        df1 = df1.astype({'quantity': 'float', 'amount': 'float'})
        df1['avg_price'] = (-(df1['amount']+df1['fee'])/ df1['quantity']).apply(lambda x: round(x, 2))
        del df1['amount'], df1['fee']
        stocks = loads(df1.to_json(orient='index'))
        stocks = [{i:stocks[i]} for i in stocks.keys()]

        return {'stocks':stocks}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    

@app.get("/calculate_profit", response_model=ProfitResponse)
async def calculate_profit(
    country: str = Query("US", description="Country code")
):
    try:
        order_set = get_history(country)
        
        # Convert to DataFrame and parse dates
        df = pd.DataFrame(order_set).sort_values(by=['date', 'time'])
        df['date'] = pd.to_datetime(df['date'])
        
        # Get unique tickers
        tickers = list(set(df['ticker']))
        
        yearly_total_profit = {}
        stocks = []
        
        for tic in tickers:
            stock_yearly_profit = {}
            dft = df[df['ticker'] == tic].copy()

            # If total buy quantity equals total sell quantity, use simple profit calculation
            if abs(dft.quantity.sum()) < 1e-9:
                total_profit_for_stock = dft.amount.sum() + dft.fee.sum()
                sells = dft[dft['order_type'] == 'sell']
                total_sell_value = abs(sells['amount'].sum())

                if total_sell_value > 0:
                    for _, sell_row in sells.iterrows():
                        sell_year = str(sell_row.date.year)
                        # Distribute profit proportionally to sell value
                        profit_share = (abs(sell_row.amount) / total_sell_value) * total_profit_for_stock
                        
                        stock_yearly_profit.setdefault(sell_year, 0)
                        stock_yearly_profit[sell_year] += profit_share
                        
                        yearly_total_profit.setdefault(sell_year, 0)
                        yearly_total_profit[sell_year] += profit_share
                
                stock_holdings = {'detail': [], 'total': 0, 'avg_price': 0, 'current_price': 0}

            else: # FIFO logic for stocks with remaining holdings
                holdings_queue = []  # FIFO queue for buy orders
                for _, row in dft.iterrows():
                    if row.order_type == 'buy':
                        holdings_queue.append({'price': row.price, 'quantity': row.quantity})
                    else:  # order_type == 'sell'
                        sell_year = str(row.date.year)
                        sell_price = row.price
                        sell_quantity_abs = abs(row.quantity)
                        
                        yearly_total_profit.setdefault(sell_year, 0)
                        stock_yearly_profit.setdefault(sell_year, 0)

                        quantity_to_sell = sell_quantity_abs
                        
                        while quantity_to_sell > 0 and holdings_queue:
                            buy_order = holdings_queue[0]
                            buy_price = buy_order['price']
                            buy_quantity = buy_order['quantity']
                            
                            match_quantity = min(quantity_to_sell, buy_quantity)
                            
                            profit_on_match = (sell_price * match_quantity * 0.9975) - (buy_price * match_quantity * 1.0025)
                            
                            yearly_total_profit[sell_year] += profit_on_match
                            stock_yearly_profit[sell_year] += profit_on_match
                            
                            quantity_to_sell -= match_quantity
                            buy_order['quantity'] -= match_quantity
                            
                            if buy_order['quantity'] < 1e-9:
                                holdings_queue.pop(0)

                # Calculate remaining holdings info
                stock_holdings = {}
                remaining_holdings_detail = []
                total_quantity = 0
                total_cost = 0
                
                for h in holdings_queue:
                    qty = h['quantity']
                    price = h['price']
                    if qty > 1e-9:
                        remaining_holdings_detail.append((price, qty))
                        total_quantity += qty
                        total_cost += price * qty
                
                stock_holdings['detail'] = remaining_holdings_detail
                stock_holdings['total'] = total_quantity
                stock_holdings['avg_price'] = round(total_cost / total_quantity, 2) if total_quantity > 0 else 0

            # Add exchange code to holdings
            if country == 'US':
                stock_holdings['exchange'] = dft.iloc[0].get('exchange', 'NASD')
            else:
                stock_holdings['exchange'] = ''

            # Round the profits for the current stock
            for year, profit in stock_yearly_profit.items():
                stock_yearly_profit[year] = round(profit, 2)

            # Create the stock object for the response
            stock_response_obj = {
                'yearly_profit': stock_yearly_profit,
                'holdings': stock_holdings
            }
            stocks.append({tic: stock_response_obj})

        # Round total profits
        for year, profit in yearly_total_profit.items():
            yearly_total_profit[year] = round(profit, 2)
            
        # Create final response
        final_response = {
            'yearly_total_profit': yearly_total_profit,
            'stocks': stocks
        }
        
        return final_response
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/account_balance")
async def get_account_balance():
    try:
        account = kis.account()
        balance = account.balance()

        # 현금 잔고 처리
        krw_deposit = balance.deposits.get('KRW')
        usd_deposit = balance.deposits.get('USD')

        krw_cash = krw_deposit.amount if krw_deposit else 0
        usd_cash = usd_deposit.amount if usd_deposit else 0
        exchange_rate = usd_deposit.exchange_rate if usd_deposit and usd_deposit.exchange_rate else 1.0
        
        usd_cash_in_krw = usd_cash * exchange_rate

        cash_response = {
            "krw": krw_cash,
            "usd": usd_cash,
            "usd_in_krw": round(usd_cash_in_krw)
        }
        
        # 주식 잔고 처리
        stocks_response = []
        if balance.stocks:
            for stock in balance.stocks:
                if stock.market == 'KRX':
                    stocks_response.append({
                        "name": stock.name,
                        "ticker": stock.symbol,
                        "quantity": stock.qty,
                        "average_price": round((stock.amount - stock.profit) / stock.qty, 2) if stock.qty > 0 else 0,
                        "current_price": stock.price,
                        "valuation": stock.amount,
                        "profit_loss": stock.profit,
                        "profit_loss_ratio": stock.profit_rate,
                        "market": stock.market,
                        "currency": "KRW"
                    })
                else: # 해외 주식
                    valuation_usd = stock.amount
                    profit_loss_usd = stock.profit
                    current_price_usd = stock.price
                    average_price_usd = (valuation_usd - profit_loss_usd) / stock.qty if stock.qty > 0 else 0

                    stocks_response.append({
                        "name": stock.name,
                        "ticker": stock.symbol,
                        "quantity": stock.qty,
                        "average_price": round(average_price_usd, 2),
                        "current_price": round(current_price_usd, 2),
                        "valuation": round(valuation_usd * exchange_rate),
                        "valuation_usd": valuation_usd,
                        "profit_loss": round(profit_loss_usd * exchange_rate),
                        "profit_loss_usd": profit_loss_usd,
                        "profit_loss_ratio": stock.profit_rate,
                        "market": stock.market,
                        "currency": "USD"
                    })

        # Add USD cash as a stock-like entry for frontend compatibility
        stocks_response.append({
            "name": "USD Cash",
            "ticker": "USD",
            "quantity": usd_cash,
            "average_price": 1.0, # USD cash price is 1.0
            "current_price": 1.0, # USD cash price is 1.0
            "valuation": round(usd_cash * exchange_rate),
            "valuation_usd": usd_cash,
            "profit_loss": 0.0,
            "profit_loss_usd": 0.0,
            "profit_loss_ratio": 0.0,
            "market": "CASH", # Custom market for cash
            "currency": "USD"
        })

        # Add KRW cash as a stock-like entry for frontend compatibility
        stocks_response.append({
            "name": "KRW Cash",
            "ticker": "KRW",
            "quantity": krw_cash,
            "average_price": 1.0, # KRW cash price is 1.0
            "current_price": 1.0, # KRW cash price is 1.0
            "valuation": krw_cash,
            "valuation_usd": round(krw_cash / exchange_rate, 2) if exchange_rate > 0 else 0.0,
            "profit_loss": 0.0,
            "profit_loss_usd": 0.0,
            "profit_loss_ratio": 0.0,
            "market": "CASH", # Custom market for cash
            "currency": "KRW"
        })

        return {
            "cash": cash_response,
            "stocks": stocks_response,
            "exchange_rate": exchange_rate
        }
        
    except Exception as e:
        import traceback
        print(f"Error in /account_balance: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# Initialize PyKis client for pension account
pension_kis = PyKis(
    id=os.getenv("KIS_ID"),
    account=os.getenv("KIS_ACNT2"),
    appkey=os.getenv("KIS_APPKEY2"),
    secretkey=os.getenv("KIS_SECRET2"),
    keep_token=True,
)

@app.get("/account_balance_pension")
async def get_account_balance_pension():
    try:
        account = pension_kis.account()
        balance = account.balance()

        # 현금 잔고 처리 (기존 get_account_balance와 동일)
        krw_deposit = balance.deposits.get('KRW')
        usd_deposit = balance.deposits.get('USD')

        krw_cash = krw_deposit.amount if krw_deposit else 0
        usd_cash = usd_deposit.amount if usd_deposit else 0
        exchange_rate = usd_deposit.exchange_rate if usd_deposit and usd_deposit.exchange_rate else 1.0
        
        usd_cash_in_krw = usd_cash * exchange_rate

        cash_response = {
            "krw": krw_cash,
            "usd": usd_cash,
            "usd_in_krw": round(usd_cash_in_krw)
        }
        
        # 주식 잔고 처리 (기존 get_account_balance와 동일)
        stocks_response = []
        if balance.stocks:
            for stock in balance.stocks:
                if stock.market == 'KRX':
                    stocks_response.append({
                        "name": stock.name,
                        "ticker": stock.symbol,
                        "quantity": stock.qty,
                        "average_price": round((stock.amount - stock.profit) / stock.qty, 2) if stock.qty > 0 else 0,
                        "current_price": stock.price,
                        "valuation": stock.amount,
                        "profit_loss": stock.profit,
                        "profit_loss_ratio": stock.profit_rate,
                        "market": stock.market,
                        "currency": "KRW"
                    })
                else: # 해외 주식
                    valuation_usd = stock.amount
                    profit_loss_usd = stock.profit
                    current_price_usd = stock.price
                    average_price_usd = (valuation_usd - profit_loss_usd) / stock.qty if stock.qty > 0 else 0

                    stocks_response.append({
                        "name": stock.name,
                        "ticker": stock.symbol,
                        "quantity": stock.qty,
                        "average_price": round(average_price_usd, 2),
                        "current_price": round(current_price_usd, 2),
                        "valuation": round(valuation_usd * exchange_rate),
                        "valuation_usd": valuation_usd,
                        "profit_loss": round(profit_loss_usd * exchange_rate),
                        "profit_loss_usd": profit_loss_usd,
                        "profit_loss_ratio": stock.profit_rate,
                        "market": stock.market,
                        "currency": "USD"
                    })

        return {
            "cash": cash_response,
            "stocks": stocks_response,
            "exchange_rate": exchange_rate
        }
        
    except Exception as e:
        import traceback
        print(f"Error in /account_balance_pension: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/ohlcv")
async def get_ohlcv(ticker: str, timeframe: str = 'D'):
    """
    주기별 ohlcv 데이터를 조회합니다.
    - timeframe: 'D' (일봉), 'H' (시간봉), 'M' (분봉)
    """
    try:
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
        return {"market": stock.market, "data": ohlcv_data}
    except Exception as e:
        print(f"Error getting ohlcv for {ticker}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/current_price/{country}/{ticker}")
async def get_current_price(country: str, ticker: str):
    try:
        price = kis.stock(ticker).quote().price
        return {"current_price": price}
    except Exception as e:
        print(f"Error in /current_price for {ticker} ({country}): {e}")
        raise HTTPException(status_code=500, detail=f"Error fetching price for {ticker}: {e}")

#if __name__ == "__main__":
    #import uvicorn
    #uvicorn.run(app, host="0.0.0.0", port=8000)