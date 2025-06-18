from fastapi import FastAPI, HTTPException, Query
from datetime import date, datetime, timedelta
from typing import Optional, List, Dict
from pydantic import BaseModel
from pykis import PyKis, KisAccount, KisDailyOrders
import pandas as pd
from dotenv import load_dotenv
import os, pytz

# Get the New York time zone
nyc_timezone = pytz.timezone('America/New_York')


load_dotenv()

app = FastAPI(title="Trading Result API")

# Request model for date range
class DateRange(BaseModel):
    start_date: str  # YYYY-MM-DD format
    end_date: str    # YYYY-MM-DD format
    country: str     # 'US' or 'KR'

# Response model for order details
class OrderResponse(BaseModel):
    date: str
    account: str
    order_type: str
    ticker: str
    quantity: int
    price: float
    amount: float
    fee: float

@app.get("/health")
async def health_check():
    return {"status": "healthy"}


@app.get("/trading/orders", response_model=List[OrderResponse])
async def get_trading_orders(
    country: str = 'US',
    start_date: str = Query(...),
    end_date: str = Query(...),
):
    try:
        # Initialize PyKis
        kis = PyKis(
            id=os.getenv('KIS_ID'),
            account=os.getenv('KIS_ACNT01'),
            appkey=os.getenv('KIS_ACNT01_ACCESS_KEY'),
            secretkey=os.getenv('KIS_ACNT01_SECRET_KEY'),
            keep_token=True
        )

        # Parse dates
        start_date = datetime.strptime(start_date, "%Y-%m-%d").date()
        end_date = datetime.strptime(end_date, "%Y-%m-%d").date()
        country = country.upper()

        if country not in ['US', 'KR']:
            raise HTTPException(status_code=400, detail="Country must be 'US' or 'KR'")

        # Get account and daily orders
        account: KisAccount = kis.account()
        daily_orders: KisDailyOrders = account.daily_orders(
            start=start_date,
            end=end_date,
            country=country
        )

        # Process orders
        order_list = []
        for ord in daily_orders.orders:
            if ord.executed_qty > 0:
                acn = daily_orders.orders[0].order_number.account_number
                order = OrderResponse(
                    date=ord.order_number.time.strftime('%Y-%m-%d %H:%M:%S'),
                    account=f"{acn.number}-{acn.code}",
                    order_type=ord.type,
                    ticker=ord.order_number.symbol,
                    quantity=ord.executed_qty,
                    price=ord.price,
                    amount=ord.executed_qty * ord.price,
                    fee=float(ord.executed_qty) * float(ord.price) * 0.0025
                )
                order_list.append(order)

        return order_list

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/trading/result")
async def get_trading_orders(
    country: str = 'US',
    start_date: str = '2025-01-01',
    end_date: str = datetime.now(nyc_timezone).strftime('%Y-%m-%d'),
):
    try:
        # Initialize PyKis
        kis = PyKis(
            id=os.getenv('KIS_ID'),
            account=os.getenv('KIS_ACNT01'),
            appkey=os.getenv('KIS_ACNT01_ACCESS_KEY'),
            secretkey=os.getenv('KIS_ACNT01_SECRET_KEY'),
            keep_token=True
        )

        # Parse dates
        start_date = datetime.strptime(start_date, "%Y-%m-%d").date()
        end_date = datetime.strptime(end_date, "%Y-%m-%d").date()
        country = country.upper()

        if country not in ['US', 'KR']:
            raise HTTPException(status_code=400, detail="Country must be 'US' or 'KR'")

        # Get account and daily orders
        account: KisAccount = kis.account()
        daily_orders: KisDailyOrders = account.daily_orders(
            start=start_date,
            end=end_date,
            country=country
        )

        # Process orders
        order_list = []
        for ord in daily_orders.orders:
            if ord.executed_qty > 0:
                acn = daily_orders.orders[0].order_number.account_number
                order = {
                    'date':ord.order_number.time.strftime('%Y-%m-%d %H:%M:%S'),
                    #account=f"{acn.number}-{acn.code}",
                    'order_type':ord.type,
                    'ticker':ord.order_number.symbol,
                    'quantity':ord.executed_qty,
                    'price':ord.price}
                order_list.append(order)

        df = pd.DataFrame(order_list).sort_values('date')
        tickers = list(set(df['ticker']))

        result = {}
        for tic in tickers:
            df1 = df.query(f"ticker == '{tic}'")
            df1.loc[:,'quantity'] = df1['quantity'].astype(float)
            df1.loc[:,'price'] = df1['price'].astype(float)
            b, s = df1.query("order_type == 'buy'"), df1.query("order_type == 'sell'")
            if b['quantity'].sum() == s['quantity'].sum():
                profit = sum(s['price'] * s['quantity'] - s['fee']) - sum(b['price'] * b['quantity'] + b['fee'])
                result[tic] = {
                    'profit': profit,
                    'holdings': float(0),
                    'price_avg': float(0),
                    'detail': [],
                    'year': df1.iloc[-1]['date'][:4]
                }
                continue

            stocks, profit = [], 0
            for index, row in df1.iterrows():
                if row['order_type'] == 'buy':
                    stocks.append((row['price'], row['quantity']))
                else:
                    a = stocks.pop(0)
                    b = row['quantity']
                    while b > 0:
                        profit += float(row['quantity'] * min(b, a[1])) * 0.9975 - float(a[0] * min(b, a[1])) * 0.10025
                        b -= a[1]
                        if b < 0:
                            stocks.insert(0, (a[0], -b))
            result[tic] = {
                'profit': profit,
                'holdings': float(sum(i[1] for i in stocks)),
                'price_avg': float(sum(i[0] * i[1] for i in stocks) / sum(i[1] for i in stocks) if stocks else 0),
                'detail': stocks,
                'year': df1.iloc[-1]['date'][:4]
            }


        return result

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))



if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
