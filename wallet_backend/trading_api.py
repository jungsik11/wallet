from fastapi import FastAPI, HTTPException
from datetime import date, datetime, timedelta
from typing import Optional, List, Dict
from pydantic import BaseModel
from pykis import PyKis, KisAccount, KisDailyOrders
from dotenv import load_dotenv
import os

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

@app.post("/trading/orders", response_model=List[OrderResponse])
async def get_trading_orders(date_range: DateRange):
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
        start_date = datetime.strptime(date_range.start_date, "%Y-%m-%d").date()
        end_date = datetime.strptime(date_range.end_date, "%Y-%m-%d").date()
        country = date_range.country.upper()

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
                    'date': ord.order_number.time.strftime('%Y-%m-%d %H:%M:%S'),
                    'account': f"{acn.number}-{acn.code}",
                    'order_type': ord.type,
                    'ticker': ord.order_number.symbol,
                    'quantity': ord.executed_qty,
                    'price': ord.price,
                    'amount': ord.executed_qty * ord.price,
                    'fee': float(ord.executed_qty) * float(ord.price) * 0.0025
                }
                order_list.append(order)

        return order_list

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
