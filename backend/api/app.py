from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from datetime import datetime, date
import pandas as pd
from json import loads, dumps
import os, copy
from decimal import Decimal
from dotenv import load_dotenv
from pykis import PyKis, KisDailyOrders

# Initialize FastAPI
app = FastAPI(title="Profit Calculation API")

# Load environment variables
load_dotenv()

# Initialize PyKis client
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
    profit: float
    holdings: Dict[str, Any]

class ProfitResponse(BaseModel):
    profit: float
    stocks: List[Dict[str, StockHolding]]


class ValuationProfitResponse(BaseModel):
    stocks: List[Dict[str, Dict[str, Any]]]

    

def get_history(country):
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
            order_set.append(o)

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
        
        
        # Convert to DataFrame
        df = pd.DataFrame(order_set).sort_values(by=['date', 'time'])
        print(df)
        # Get unique tickers
        tickers = list(set(df['ticker']))
        
        # Calculate profit
        bal = {'profit': 0}
        stocks = []
        
        for tic in tickers:
            stock = {'profit': 0, 'holdings': {}}
            dft = df[df['ticker'] == tic].copy()
            
            if dft.quantity.sum() == 0:
                bal['profit'] += float(dft.amount.sum()) + dft.fee.sum()
                continue
            
            holdings = []
            for i in dft.iterrows():
                if i[1].order_type == 'buy':
                    holdings.append((i[1].price, i[1].quantity))
                else:
                    a = holdings.pop(0)
                    b = abs(i[1].quantity)
                    while b > 0:
                        if a[1] > b:
                            holdings.insert(0, (a[0], a[1]-b))
                            bal['profit'] += float(i[1].price*b)*0.9975 - float(a[0]*b)*1.0025
                            stock['profit'] += float(i[1].price*b)*0.9975 - float(a[0]*b)*1.0025
                            b = 0
                        else:
                            b -= a[1]
                            bal['profit'] += float(i[1].price*a[1])*0.9975 - float(a[0]*a[1])*1.0025
                            stock['profit'] += float(i[1].price*a[1])*0.9975 - float(a[0]*a[1])*1.0025
            
            stock['profit'] = round(stock['profit'], 2)
            stock['holdings']['detail'] = holdings
            
            if holdings:
                h = sum([i[1] for i in holdings])
                stock['holdings']['total'] = float(h)
                stock['holdings']['avg_price'] = round(sum(i[0]*i[1] for i in holdings)/h, 2)
            else:
                stock['holdings']['total'] = 0
                stock['holdings']['avg_price'] = 0
                
            stock['profit'] = round(stock['profit'],2)
            stock['holdings']['detail'] = holdings
            h = sum([i[1] for i in holdings])
            stock['holdings']['total'] = h
            stock['holdings']['avg_price'] = round(sum(i[0]*i[1] for i in holdings)/h,2) 
            stocks.append({tic:stock})
            bal['profit'] = round(bal['profit'],2)
            
        
        bal['profit'] = round(bal['profit'],2)
        bal['stocks'] = stocks
        
        return bal
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/account_balance")
async def get_account_balance():
    try:
        account = kis.account()
        balance = account.balance()
        return {"balance": repr(balance)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

#if __name__ == "__main__":
    #import uvicorn
    #uvicorn.run(app, host="0.0.0.0", port=8000)