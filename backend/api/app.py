from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from datetime import datetime, date
import pandas as pd
from json import loads, dumps
import os, copy
from decimal import Decimal
<<<<<<< Updated upstream
# from dotenv import load_dotenv
from pykis import PyKis, KisDailyOrders
=======
from dotenv import load_dotenv
from pykis import PyKis, KisDailyOrders, KisChart
from fastapi.responses import JSONResponse
from datetime import datetime, timedelta
>>>>>>> Stashed changes
import time
import psycopg2
from psycopg2.pool import SimpleConnectionPool

# Initialize FastAPI
app = FastAPI(title="Profit Calculation API")

# Load environment variables
# load_dotenv()

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
        
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail=f"{country}_trade_history.csv not found.")
    except Exception as e:
        print(f"Error in calculate_profit for {country}: {e}")
        raise HTTPException(status_code=500, detail=f"An error occurred while calculating profit: {e}")

@app.get("/balance")
def get_balance():
    try:
        account = kis.account()
<<<<<<< Updated upstream
        balance_list = account.balance().stocks

        us_holdings = []
        kr_holdings = []

        for holding in balance_list:
            # Check if the holding is overseas or domestic

            # Domestic stocks have a 6-digit numeric symbol
            if holding.symbol.isdigit() and len(holding.symbol) == 6:
                kr_holdings.append({
                    "ticker": holding.symbol,                   
                    "quantity": int(holding.qty),
                    "avg_price": float(holding.amount/holding.qty),
                    "current_price": float(holding.price),
                    "pnl": float(holding.profit),
                })
            else:
                us_holdings.append({
                    "ticker": holding.symbol,                   
                    "quantity": int(holding.qty),
                    "avg_price": float(holding.amount/holding.qty),
                    "current_price": float(holding.price),
                    "pnl": float(holding.profit),
                })
            
        return {"US": us_holdings, "KR": kr_holdings}
    except Exception as e:
        print(f"Error in /balance: {e}")
        raise HTTPException(status_code=500, detail=f"An error occurred while fetching account balance: {e}")

@app.get("/portfolio_summary")
def get_portfolio_summary():
    try:
        balance = kis.account().balance()

        krw_deposit = balance.deposits.get('KRW').amount if balance.deposits.get('KRW') else 0
        usd_deposit = balance.deposits.get('USD').amount if balance.deposits.get('USD') else 0
        exchange_rate = balance.deposits.get('USD').exchange_rate if balance.deposits.get('USD') else 1.0

        total_assets_krw = krw_deposit + (usd_deposit * exchange_rate)
        pie_chart_data = [
            {"asset": "KRW 예수금", "value_krw": float(krw_deposit)},
            {"asset": "USD 예수금", "value_krw": float(usd_deposit * exchange_rate)}
        ]

        for stock in balance.stocks:
            stock_value = stock.price * stock.qty
            # Domestic stocks are already in KRW
            is_domestic = stock.symbol.isdigit() and len(stock.symbol) == 6
            stock_value_krw = stock_value if is_domestic else stock_value * exchange_rate
            
            total_assets_krw += stock_value_krw
            pie_chart_data.append({
                "asset": stock.symbol,
                "value_krw": float(stock_value_krw)
            })

        return {
            "total_assets_krw": float(total_assets_krw),
            "krw_deposit": float(krw_deposit),
            "usd_deposit": float(usd_deposit),
            "exchange_rate": float(exchange_rate),
            "pie_chart_data": pie_chart_data
        }

    except Exception as e:
        print(f"Error in /portfolio_summary: {e}")
        raise HTTPException(status_code=500, detail=f"An error occurred: {e}")

@app.get("/ohlcv/{ticker}")
def get_ohlcv(ticker: str, timeframe: str = "1d"):
    try:
        if timeframe == '1m':
            # Fetch 1-minute data for the last few hours
            chart = kis.stock(ticker).chart(period=1) 
        elif timeframe == '1h':
            # Fetch 1-hour data
            chart = kis.stock(ticker).chart("1d", period='h')
        else: # Default to '1d'
            # Fetch daily data for the last 90 days
            chart = kis.stock(ticker).chart("3M")
        
        # Convert Kis...ChartBar objects to a list of dictionaries
        chart_data = [
            {
                "time": bar.time.isoformat(),
=======
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
>>>>>>> Stashed changes
                "open": bar.open,
                "high": bar.high,
                "low": bar.low,
                "close": bar.close,
                "volume": bar.volume
<<<<<<< Updated upstream
            }
            for bar in chart.bars
        ]
        return chart_data
    except Exception as e:
        print(f"Error fetching OHLCV for {ticker} with timeframe {timeframe}: {e}")
        raise HTTPException(status_code=500, detail=f"Could not fetch chart data for {ticker}: {e}")
=======
            } for bar in chart.bars
        ]
        return {"market": stock.market, "data": ohlcv_data}
    except Exception as e:
        print(f"Error getting ohlcv for {ticker}: {e}")
        raise HTTPException(status_code=500, detail=str(e))
>>>>>>> Stashed changes


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
    print(f"Received chat message: {chat_message.dict()}")
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
            print(f"Inserted new message with ID: {new_message[0]}")
            conn.commit()
            print("Commit successful.")
            return ChatMessageResponse(
                id=new_message[0],
                sender=new_message[1],
                message=new_message[2],
                model_name=new_message[3],
                created_at=new_message[4]
            )
    except Exception as e:
        print(f"Database error occurred: {e}")
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

class TickersRequest(BaseModel):
    country: str
    tickers: List[str]

@app.post("/current_prices")
async def get_current_prices_batch(request: TickersRequest):
    prices = {}
    for ticker in request.tickers:
        retries = 3
        while retries > 0:
            try:
                price = kis.stock(ticker).quote().price
                prices[ticker] = float(price)
                time.sleep(0.3) # Respect API limits
                break # Success, exit while loop
            except Exception as e:
                error_message = str(e)
                print(f"Error for {ticker}: {error_message}")
                if '호출 횟수' in error_message: # Rate limit error
                    print(f"Rate limit hit for {ticker}. Retrying...")
                    retries -= 1
                    time.sleep(1) # Wait longer before retrying
                else: # Other errors (e.g., invalid ticker)
                    prices[ticker] = 0.0
                    break # Don't retry for this ticker
        if retries == 0:
            print(f"Failed to fetch price for {ticker} after multiple retries.")
            prices[ticker] = 0.0

    return prices

#if __name__ == "__main__":

    #import uvicorn
    #uvicorn.run(app, host="0.0.0.0", port=8000)