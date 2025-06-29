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
import time
import psycopg2
from psycopg2.pool import SimpleConnectionPool

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
        return {"balance": repr(balance)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/current_price/{country}/{ticker}")
async def get_current_price(country: str, ticker: str):
    try:
        price = kis.stock(ticker).quote().price
        return {"current_price": price}
    except Exception as e:
        print(f"Error in /current_price for {ticker} ({country}): {e}")
        raise HTTPException(status_code=500, detail=f"Error fetching price for {ticker}: {e}")


# --- Chat History API ---

# Database connection pool
db_pool = None

def get_db_pool():
    global db_pool
    if db_pool is None:
        try:
            db_pool = SimpleConnectionPool(
                minconn=1,
                maxconn=10,
                user=os.getenv("DB_USER", "user"),
                password=os.getenv("DB_PASSWORD", "password"),
                host=os.getenv("DB_HOST", "db"),
                port=os.getenv("DB_PORT", "5432"),
                database=os.getenv("DB_NAME", "chatdb")
            )
            print("Database connection pool created successfully.")
        except Exception as e:
            print(f"Error creating database connection pool: {e}")
            raise
    return db_pool

# Pydantic models for chat history
class ChatMessageCreate(BaseModel):
    sender: str
    message: str
    model_name: Optional[str] = None

class ChatMessageResponse(BaseModel):
    id: int
    sender: str
    message: str
    model_name: Optional[str] = None
    created_at: datetime

@app.on_event("startup")
async def startup_event():
    get_db_pool()

@app.on_event("shutdown")
async def shutdown_event():
    global db_pool
    if db_pool:
        db_pool.closeall()
        print("Database connection pool closed.")

@app.post("/chat", response_model=ChatMessageResponse)
async def create_chat_message(chat_message: ChatMessageCreate):
    pool = get_db_pool()
    conn = None
    try:
        conn = pool.getconn()
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO chat_history (sender, message, model_name)
                VALUES (%s, %s, %s)
                RETURNING id, sender, message, model_name, created_at
                """,
                (chat_message.sender, chat_message.message, chat_message.model_name)
            )
            new_message = cur.fetchone()
            conn.commit()
            return ChatMessageResponse(
                id=new_message[0],
                sender=new_message[1],
                message=new_message[2],
                model_name=new_message[3],
                created_at=new_message[4]
            )
    except Exception as e:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=f"Database error: {e}")
    finally:
        if conn:
            pool.putconn(conn)

@app.get("/chat", response_model=List[ChatMessageResponse])
async def get_chat_history():
    pool = get_db_pool()
    conn = None
    try:
        conn = pool.getconn()
        with conn.cursor() as cur:
            cur.execute("SELECT id, sender, message, model_name, created_at FROM chat_history ORDER BY created_at ASC")
            history = cur.fetchall()
            return [
                ChatMessageResponse(
                    id=row[0],
                    sender=row[1],
                    message=row[2],
                    model_name=row[3],
                    created_at=row[4]
                ) for row in history
            ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")
    finally:
        if conn:
            pool.putconn(conn)

#if __name__ == "__main__":
    #import uvicorn
    #uvicorn.run(app, host="0.0.0.0", port=8000)