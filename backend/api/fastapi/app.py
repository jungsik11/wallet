"""
FastAPI application for providing stock and pension data from the Korea Investment & Securities (KIS) API,
now using the KIS Trade MCP server.
"""

# --- Imports ---

import os
import traceback
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional
import logging
from ranking_chart_service import get_ranked_stocks

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
import asyncio

from utils import call_mcp_tool, MCP_STOCK_SERVER_URL, MCP_PENSION_SERVER_URL, StockHolding, ProfitResponse

# --- Helper Functions ---

# --- Imports ---

import os
import traceback
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional
import logging
from ranking_chart_service import get_ranked_stocks

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
import asyncio

def safe_float(value: Any, default: float = 0.0) -> float:
    """Safely convert a value to a float, returning a default on failure."""
    if value is None or value == '':
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default

def safe_int(value: Any, default: int = 0) -> int:
    """Safely convert a value to an integer, returning a default on failure."""
    if value is None or value == '':
        return default
    try:
        # Float string to int conversion (e.g., "123.00")
        return int(float(value))
    except (ValueError, TypeError):
        return default

# --- FastAPI and KIS Initialization ---

# Load environment variables from .env file
load_dotenv()

# Initialize FastAPI app
app = FastAPI(title="Profit Calculation API")



# --- API Endpoints ---

@app.get("/all_profit_data")
async def get_all_profit_data(country: str = Query(..., description="Country code (US or KR)")):
    current_year = datetime.now().year
    years = list(range(2021, current_year + 1))
    
    tasks = [calculate_profit(country=country, year=year) for year in years]
    
    profit_data = {}
    try:
        results = await asyncio.gather(*tasks, return_exceptions=True)
        for i, year in enumerate(years):
            if not isinstance(results[i], Exception):
                profit_data[str(year)] = results[i]
            else:
                logging.error(f"Error fetching profit data for {country} year {year}: {results[i]}")
                profit_data[str(year)] = {} # Return empty dict on error for a specific year
    except Exception as e:
        logging.error(f"Unhandled exception in get_all_profit_data for {country}: {e}")
        # If the gather itself fails, return empty data for all years
        for year in years:
            profit_data[str(year)] = {}
            
    return profit_data

@app.get("/all_balance_data")
async def get_all_balance_data():
    tasks = [
        get_account_balance(country="US"),
        get_account_balance(country="KR"),
        get_account_balance_pension()
    ]
    
    us_balance = {}
    kr_balance = {}
    pension_balance = {}

    try:
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        if not isinstance(results[0], Exception):
            us_balance = results[0]
        else:
            logging.error(f"Error fetching US balance data: {results[0]}")
        
        if not isinstance(results[1], Exception):
            kr_balance = results[1]
        else:
            logging.error(f"Error fetching KR balance data: {results[1]}")

        if not isinstance(results[2], Exception):
            pension_balance = results[2]
        else:
            logging.error(f"Error fetching pension balance data: {results[2]}")

    except Exception as e:
        logging.error(f"Unhandled exception in get_all_balance_data: {e}")
        # All will be empty if gather itself fails
    
    return {
        "us_balance_data": us_balance,
        "kr_balance_data": kr_balance,
        "pension_balance_data": pension_balance,
    }

@app.get("/account_balance")
async def get_account_balance(country: str = Query(None, description="Country code (US or KR)")):
    if country == "KR":
        params = {
            "cano": os.getenv("KIS_ACCT_STOCK1"), "acnt_prdt_cd": os.getenv("KIS_PROD_TYPE1"),
            "env_dv": "real", # Added missing env_dv parameter
            "afhr_flpr_yn": "N", "inqr_dvsn": "01", "unpr_dvsn": "01",
            "fund_sttl_icld_yn": "N", "fncg_amt_auto_rdpt_yn": "N", "prcs_dvsn": "00"
        }
        logging.info(f"DEBUG: Calling MCP tool for KR account balance with api_type='domestic_stock', specific_api_type='inquire_balance', params={params}")
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_balance", params)
        logging.info(f"DEBUG: Raw data received from MCP tool for KR account balance: {data}")
        stocks = data[0].get("output1", [])
        summary = data[0].get("output2", [{}])[0]

        return {
            "cash": {"krw": safe_int(summary.get("dnca_tot_amt"))},
            "stocks": [
                {
                    "name": s.get("prdt_name"), "ticker": s.get("pdno"), "quantity": safe_int(s.get("hldg_qty")),
                    "profit_loss_ratio": safe_float(s.get("evlu_pfls_rt")), "market": "KRX",
                    "average_price": safe_float(s.get("pchs_avg_pric")), "current_price": safe_float(s.get("prpr")),
                    "valuation": safe_int(s.get("evlu_amt")), "profit_loss": safe_int(s.get("evlu_pfls_amt")), "currency": "KRW"
                } for s in stocks
            ]
        }
    elif country == "US":
        params = {
            "wcrc_frcr_dvsn_cd": "02",  # 02 : 외화 (Foreign Currency)
            "natn_cd": "840",           # 840 : 미국 (USA)
            "tr_mket_cd": "00",         # 00 : 전체 (All Markets)
            "inqr_dvsn_cd": "00",       # 00 : 전체 (All Inquiry Divisions)
        }
        logging.info(f"DEBUG: Calling MCP tool for US account balance with api_type='overseas_stock', specific_api_type='inquire_present_balance', params={params}")
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_present_balance", params)
        logging.info(f"DEBUG: Raw data received from MCP tool for US account balance: {data}")
        
        stocks = data[0].get("output1", [])
        summary_output2 = data[0].get("output2", [{}])[0]

        return {
            "cash": {"usd": safe_float(summary_output2.get("frcr_dncl_amt_2"))},
            "stocks": [
                {
                    "name": s.get("prdt_name"),
                    "ticker": s.get("pdno"),
                    "quantity": safe_int(s.get("ccld_qty_smtl1")),
                    "profit_loss_ratio": safe_float(s.get("evlu_pfls_rt1")),
                    "market": s.get("tr_mket_name"),
                    "average_price": safe_float(s.get("avg_unpr3")), 
                    "current_price": safe_float(s.get("ovrs_now_pric1")),
                    "valuation_usd": safe_float(s.get("frcr_evlu_amt2")), 
                    "profit_loss_usd": safe_float(s.get("evlu_pfls_amt2")),
                    "currency": s.get("buy_crcy_cd")
                } for s in stocks
            ],
            "exchange_rate": safe_float(summary_output2.get('frst_bltn_exrt', 0 )) # Add exchange rate to the response
        }    
    else:
        raise HTTPException(status_code=400, detail="Country must be KR or US")

@app.get("/calculate_profit")
async def calculate_profit(country: str = Query(..., description="Country code (US or KR)"), year: int = Query(..., description="Year for profit calculation (e.g., 2021)")):
    
    inqr_strt_dt = f"{year}0101"
    inqr_end_dt = f"{year}1231"

    if country == "US":
        us_params = {
            "cano": os.getenv("KIS_ACNT")[:8],
            "acnt_prdt_cd": os.getenv("KIS_ACNT")[9:],
            "ovrs_excg_cd": "NASD",  # For US, use NASD for consolidated
            "natn_cd": "",           # Empty for default
            "crcy_cd": "USD",
            "pdno": "",              # Empty for all products
            "inqr_strt_dt": inqr_strt_dt,
            "inqr_end_dt": inqr_end_dt,
            "wcrc_frcr_dvsn_cd": "01", # 01: Foreign Currency
            "FK200": "",
            "NK200": "",
        }
        us_data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_period_profit", us_params)

        us_stocks_profit_data = us_data[0].get("output1", [])
        us_overall_profit_summary = us_data[0].get("output2", [{}])[0]

        total_usd_profit_for_year = safe_float(us_overall_profit_summary.get("ovrs_rlzt_pfls_tot_amt"))
        
        all_processed_stocks_usd: Dict[str, Dict[str, Any]] = {} # ticker -> {name, market, currency, cumulative_profit_usd}
        for s in us_stocks_profit_data:
            ticker = s.get("ovrs_pdno")
            if ticker not in all_processed_stocks_usd:
                all_processed_stocks_usd[ticker] = {
                    "name": s.get("ovrs_item_name"),
                    "ticker": ticker,
                    "market": s.get("ovrs_excg_cd"),
                    "currency": "USD",
                    "yearly_profit_usd": 0.0 # Changed to yearly_profit_usd
                }
            stock_usd_profit = safe_float(s.get("ovrs_rlzt_pfls_amt"))
            all_processed_stocks_usd[ticker]["yearly_profit_usd"] += stock_usd_profit # Changed to yearly_profit_usd
        
        final_stocks_output_usd = []
        for ticker, details in all_processed_stocks_usd.items():
            final_stocks_output_usd.append(StockHolding(
                yearly_profit={"USD": details["yearly_profit_usd"]}, # Changed to yearly_profit_usd
                holdings={
                    "name": details["name"],
                    "ticker": details["ticker"],
                    "market": details["market"],
                    "currency": details["currency"]
                }
            ))
        
        logging.info(f"DEBUG: US yearly_profit_usd for {year}: {total_usd_profit_for_year}")
        return {"yearly_profit_usd": total_usd_profit_for_year, "stocks": final_stocks_output_usd}

    elif country == "KR":
        kr_all_trades_params = {
            "cano": os.getenv("KIS_ACNT")[:8],
            "acnt_prdt_cd": os.getenv("KIS_ACNT")[9:],
            "inqr_strt_dt": inqr_strt_dt,
            "inqr_end_dt": inqr_end_dt,
            "sort_dvsn": "00",
            "cblc_dvsn": "00",
            "pdno": "",  # Empty to get all stocks with trades
            "tr_cont": "",
        }
        kr_all_trades_data = await call_mcp_tool(
            MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_period_trade_profit", kr_all_trades_params
        )
        
        kr_stocks_with_trades = kr_all_trades_data[0].get("output1", [])
        kr_overall_summary = kr_all_trades_data[0].get("output2", [{}])[0]
        
        total_krw_profit_for_year = safe_float(kr_overall_summary.get("tot_rlzt_pfls", kr_overall_summary.get("rlzt_pfls_amt")))
        
        all_processed_stocks_krw: Dict[str, Dict[str, Any]] = {} # ticker -> {name, market, currency, cumulative_profit_krw}

        # Optimized logic: Process trades from the single API call
        for trade in kr_stocks_with_trades:
            pdno = trade.get("pdno")
            prdt_name = trade.get("prdt_name")
            realized_profit = safe_float(trade.get("rlzt_pfls_amt"))

            if not pdno:
                continue

            if pdno not in all_processed_stocks_krw:
                all_processed_stocks_krw[pdno] = {
                    "name": prdt_name,
                    "ticker": pdno,
                    "market": "KRX",
                    "currency": "KRW",
                    "yearly_profit_krw": 0.0
                }
            all_processed_stocks_krw[pdno]["yearly_profit_krw"] += realized_profit
        
        final_stocks_output_krw = []
        for ticker, details in all_processed_stocks_krw.items():
            final_stocks_output_krw.append(StockHolding(
                yearly_profit={"KRW": details["yearly_profit_krw"]}, # Changed to yearly_profit_krw
                holdings={
                    "name": details["name"],
                    "ticker": details["ticker"],
                    "market": details["market"],
                    "currency": details["currency"]
                }
            ))
        logging.info(f"DEBUG: KR yearly_profit_krw for {year}: {total_krw_profit_for_year}")
        return {"yearly_profit_krw": total_krw_profit_for_year, "stocks": final_stocks_output_krw}
    
    else:
        raise HTTPException(status_code=400, detail="Country must be US or KR")

@app.get("/account_balance_pension")
async def get_account_balance_pension():
    params = {
            "cano": os.getenv("KIS_ACCT_STOCK2"), "acnt_prdt_cd": os.getenv("KIS_PROD_TYPE2"),
            "env_dv": "real", # Added missing env_dv parameter
            "afhr_flpr_yn": "N", "inqr_dvsn": "01", "unpr_dvsn": "01",
            "fund_sttl_icld_yn": "N", "fncg_amt_auto_rdpt_yn": "N", "prcs_dvsn": "00"
        }
    data = await call_mcp_tool(MCP_PENSION_SERVER_URL, "domestic_stock", "inquire_balance", params)
    stocks = data[0].get("output1", [])
    summary = data[0].get("output2", [{}])[0]
    
    return {
    "cash": {"krw": safe_int(summary.get("dnca_tot_amt"))},
    "stocks": [
        {
            "name": s.get("prdt_name"), "ticker": s.get("pdno"), "quantity": safe_int(s.get("hldg_qty")),
            "profit_loss_ratio": safe_float(s.get("evlu_pfls_rt")), "market": "KRX",
            "average_price": safe_float(s.get("pchs_avg_pric")), "current_price": safe_float(s.get("prpr")),
            "valuation": safe_int(s.get("evlu_amt")), "profit_loss": safe_int(s.get("evlu_pfls_amt")), "currency": "KRW"
        } for s in stocks
    ]
    }



@app.get("/ohlcv/{timeframe}")
async def get_ohlcv_by_timeframe(ticker: str, timeframe: str):
    today = datetime.now()
    
    # Determine date range based on timeframe
    inqr_strt_dt = ""
    inqr_end_dt = today.strftime("%Y%m%d")

    if timeframe == 'Y':
        start_date = datetime(today.year - 20, 1, 1) # Go back 20 years for yearly
        inqr_strt_dt = start_date.strftime("%Y%m%d")
    elif timeframe == 'M':
        start_date = today - timedelta(days=365 * 5) # Go back 5 years for monthly
        inqr_strt_dt = start_date.strftime("%Y%m%d")
    elif timeframe == 'W':
        start_date = today - timedelta(days=365 * 2) # Go back 2 years for weekly
        inqr_strt_dt = start_date.strftime("%Y%m%d")
    elif timeframe == 'D':
        start_date = today - timedelta(days=365) # Go back 1 year for daily
        inqr_strt_dt = start_date.strftime("%Y%m%d")
    elif timeframe == 'T': # Minute data
        # For minute data, typically a shorter range is used, e.g., last few days
        start_date = today - timedelta(days=7) # Last 7 days for minute data
        inqr_strt_dt = start_date.strftime("%Y%m%d")
        # KIS minute chart API for domestic requires end date in the future if current date is start date,
        # or can be current date if searching a past day. Let's use current date for simplicity.
        # For overseas minute, it requires start_date_time and close_date_time
    else:
        raise HTTPException(status_code=400, detail="Invalid timeframe. Choose from Y, M, W, D, T.")

    processed_ohlcv = []
    message = "OHLCV data fetched successfully."

    if ticker.isdigit(): # Domestic Stock
        if timeframe == 'T': # Minute data for domestic
            current_day_str = today.strftime("%Y%m%d")
            
            params = {
                "env_dv": "real",
                "fid_cond_mrkt_div_code": "J",
                "fid_input_iscd": ticker,
                "fid_input_hour_1": "090000", # Standard market open time
                "fid_pw_data_incu_yn": "Y",    # Include pre-market data
                "fid_etc_cls_code": ""
            }
            logging.info(f"DEBUG: Domestic minute OHLCV params for {ticker}: {params}")
            
            data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_time_itemchartprice", params)
            logging.info(f"DEBUG: Raw data from domestic minute OHLCV for {ticker}: {data}")
            ohlcv_data = data[0].get("output2", [])

            processed_ohlcv = []
            for item in ohlcv_data:
                # Ensure date and time are correctly formatted
                cntg_hour = item.get("stck_cntg_hour")
                if cntg_hour:
                    # KIS API returns cntg_hour as HHMMSS, combine with current_day_str for full datetime
                    dt_str = f"{current_day_str}T{cntg_hour[:2]}:{cntg_hour[2:4]}:{cntg_hour[4:6]}"
                    processed_ohlcv.append({
                        "date": dt_str,
                        "open": safe_float(item.get("stck_oprc")),
                        "high": safe_float(item.get("stck_hgpr")),
                        "low": safe_float(item.get("stck_lwpr")),
                        "close": safe_float(item.get("stck_clpr")), # Use stck_clpr for close price
                        "volume": safe_int(item.get("acml_vol"))
                    })
            
            logging.info(f"DEBUG: Processed domestic minute OHLCV (first 5): {processed_ohlcv[:5]}")
            logging.info(f"DEBUG: Processed domestic minute OHLCV (last 5): {processed_ohlcv[-5:]}")

            message = f"Minute OHLCV data for domestic stock fetched successfully for today."
            
        else: # Daily, Weekly, Monthly, Yearly for domestic
            period_map = {
                'Y': 'Y', 'M': 'M', 'W': 'W', 'D': 'D'
            }
            fid_period_div_code = period_map.get(timeframe, 'D')

            params = {
                "env_dv": "real",
                "fid_cond_mrkt_div_code": "J", # Always KRX for domestic stocks
                "fid_input_iscd": ticker,
                "fid_input_date_1": inqr_strt_dt,
                "fid_input_date_2": inqr_end_dt,
                "fid_period_div_code": fid_period_div_code,
                "fid_org_adj_prc": "0" # 0: Adjusted price
            }
            data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_daily_itemchartprice", params)
            ohlcv_data = data[0].get("output2", [])

            current_calendar_year = today.year
            for item in ohlcv_data:
                item_date_str = item.get("stck_bsop_date")
                year_of_data = int(item_date_str[:4])
                
                # For yearly data, set date to last day of the year for past years. For current year, use today's date.
                if timeframe == 'Y' and year_of_data < current_calendar_year:
                    formatted_date = f"{year_of_data}-12-31"
                elif timeframe == 'Y' and year_of_data == current_calendar_year:
                    formatted_date = today.strftime("%Y-%m-%d") # Use today's date for current year
                else:
                    formatted_date = f"{item_date_str[:4]}-{item_date_str[4:6]}-{item_date_str[6:8]}"

                processed_ohlcv.append({
                    "date": formatted_date,
                    "open": safe_float(item.get("stck_oprc")),
                    "high": safe_float(item.get("stck_hgpr")),
                    "low": safe_float(item.get("stck_lwpr")),
                    "close": safe_float(item.get("stck_clpr")),
                    "volume": safe_int(item.get("acml_vol"))
                })
            message = f"{timeframe} OHLCV data for domestic stock fetched successfully."

    else: # Overseas Stock
        exchanges_to_try = ["NAS", "NYS", "AMS"]
        found_exchange = None
        
        if timeframe == 'Y':
            monthly_ohlcv_data = []
            # Fetch monthly data for overseas stock to aggregate into yearly
            for exchange in exchanges_to_try:
                params_monthly = {
                    "auth": "",
                    "excd": exchange,
                    "symb": ticker,
                    "gubn": "2", # Monthly data
                    "bymd": inqr_end_dt, # End date for fetching monthly data
                    "modp": "0",
                    "env_dv": "real"
                }
                data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "dailyprice", params_monthly)
                
                if data[0] and data[0].get("output2"):
                    monthly_ohlcv_data = data[0]["output2"]
                    found_exchange = exchange
                    break
            
            if not monthly_ohlcv_data:
                message = f"Could not fetch monthly data for overseas stock '{ticker}' from any exchange. Yearly OHLCV cannot be generated."
            else:
                logging.info(f"DEBUG: Raw monthly OHLCV data for {ticker}: {monthly_ohlcv_data}")
                monthly_ohlcv_data.sort(key=lambda x: x.get('xymd', '')) # Sort ascending

                yearly_ohlcv_aggregated = []
                current_year_data = None

                for item in monthly_ohlcv_data:
                    item_date_str = item.get("xymd")
                    if not item_date_str:
                        continue
                    item_date = datetime.strptime(item_date_str, "%Y%m%d")
                    
                    year = item_date.year
                    open_price = safe_float(item.get("open"))
                    high_price = safe_float(item.get("high"))
                    low_price = safe_float(item.get("low"))
                    close_price = safe_float(item.get("clos"))
                    volume = safe_int(item.get("tvol"))

                    if current_year_data is None or current_year_data['date'].split('-')[0] != str(year):
                        if current_year_data is not None:
                            yearly_ohlcv_aggregated.append(current_year_data)
                        
                        current_year_data = {
                            "date": f"{year}-12-31", # Changed to YYYY-MM-DD format, last day of year
                            "open": open_price,
                            "high": high_price,
                            "low": low_price,
                            "close": close_price,
                            "volume": volume
                        }
                    else:
                        current_year_data['high'] = max(current_year_data['high'], high_price)
                        current_year_data['low'] = min(current_year_data['low'], low_price)
                        current_year_data['close'] = close_price
                        current_year_data['volume'] += volume
                
                if current_year_data is not None:
                    yearly_ohlcv_aggregated.append(current_year_data)
                
                # Set current year's date to today's date if it's the current calendar year, otherwise to Dec 31
                current_calendar_year = datetime.now().year
                for i in range(len(yearly_ohlcv_aggregated)):
                    year_of_data = int(yearly_ohlcv_aggregated[i]['date'].split('-')[0])
                    if year_of_data == current_calendar_year:
                        yearly_ohlcv_aggregated[i]['date'] = today.strftime("%Y-%m-%d")
                    else:
                        yearly_ohlcv_aggregated[i]['date'] = f"{year_of_data}-12-31"

                message = f"Yearly OHLCV data for overseas stock '{ticker}' generated from monthly data from {found_exchange}. Current year's data is included."
                
                processed_ohlcv = yearly_ohlcv_aggregated
                logging.info(f"DEBUG: Aggregated yearly OHLCV data for {ticker}: {processed_ohlcv}")

        elif timeframe in ['M', 'W', 'D']: # Monthly, Weekly, Daily for overseas
            gubn_map = {
                'D': '0', 'W': '1', 'M': '2'
            }
            gubn_code = gubn_map.get(timeframe)
            
            for exchange in exchanges_to_try:
                params = {
                    "auth": "",
                    "excd": exchange,
                    "symb": ticker,
                    "gubn": gubn_code,
                    "bymd": inqr_end_dt,
                    "modp": "0",
                    "env_dv": "real"
                }
                data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "dailyprice", params)
                ohlcv_data = data[0].get("output2", [])

                if ohlcv_data: # If data is found, process and return it
                    for item in ohlcv_data:
                        processed_ohlcv.append({
                            "date": item.get("xymd"),
                            "open": safe_float(item.get("open")),
                            "high": safe_float(item.get("high")),
                            "low": safe_float(item.get("low")),
                            "close": safe_float(item.get("clos")),
                            "volume": safe_int(item.get("tvol"))
                        })
                    found_exchange = exchange
                    message = f"{timeframe} OHLCV data for overseas stock fetched successfully from {found_exchange}."
                    break # Exit loop once data is found

            if not found_exchange:
                message = f"Could not fetch {timeframe} OHLCV data for overseas stock '{ticker}' from any exchange."

        elif timeframe == 'T': # Minute data for overseas
            all_ohlcv_data = []
            for exchange in ["NYS", "NAS", "AMS"]:
                params = {"auth": "", "excd": exchange, "symb": ticker, "nmin": "1", "pinc": "1", "next": "", "nrec": "120", "fill": "", "keyb": ""}
                data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_time_itemchartprice", params)
                page_data = data[0].get("output2", []) # data is a tuple (output, message)
                if page_data:
                    all_ohlcv_data = page_data
                    found_exchange = exchange
                    break
            
            if all_ohlcv_data and safe_float(all_ohlcv_data[0].get("open")) == 0:
                message = f"Overseas minute OHLCV data for '{ticker}' is empty or invalid from {found_exchange}."
            else:
                for item in all_ohlcv_data:
                    tymd = item.get('tymd')
                    xhms = item.get('xhms')
                    if tymd and xhms:
                        dt_str = f"{tymd[:4]}-{tymd[4:6]}-{tymd[6:8]}T{xhms[:2]}:{xhms[2:4]}:{xhms[4:6]}"
                        processed_ohlcv.append({
                            "date": dt_str,
                            "open": safe_float(item.get("open")),
                            "high": safe_float(item.get("high")),
                            "low": safe_float(item.get("low")),
                            "close": safe_float(item.get("last")),
                            "volume": safe_int(item.get("evol"))
                        })
                message = f"Minute OHLCV data for overseas stock fetched successfully from {found_exchange}."
            
    processed_ohlcv.sort(key=lambda x: x.get('date')) # Ensure ascending order by date
    return {"data": processed_ohlcv, "message": message}

@app.get("/current_price/{ticker}")
async def get_current_price(ticker: str):
    if not ticker.isdigit(): # Overseas
        exchanges_to_try = ["NAS", "NYS", "AMS"]
        for exchange in exchanges_to_try:
            params = {"auth": "", "excd": exchange, "symb": ticker, "env_dv": "real"}
            data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "price", params)
            if isinstance(data, list) and len(data) > 0 and data[0].get("last"):
                return {"current_price": safe_float(data[0].get("last"))}
        return {"current_price": 0.0}
    else: # Domestic
        params = {"env_dv": "real", "fid_cond_mrkt_div_code": "J", "fid_input_iscd": ticker}
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_price", params)
        if isinstance(data[0], list) and len(data[0]) > 0:
            output = data[0][0] # Assuming list of dicts, take first dict
            if output:
                return {"current_price": safe_float(output.get("stck_prpr"))}
        elif isinstance(data[0], dict):
            output = data[0].get("output", {})
            if output:
                return {"current_price": safe_float(output.get("stck_prpr"))}
        return {"current_price": 0.0}

@app.get("/stock/{ticker}")
async def get_stock_detail(ticker: str):
    if not ticker.isdigit(): # Overseas
        exchanges_to_try = ["NAS", "NYS", "AMS"]
        price_data = None
        found_exchange = None

        # First, find the correct exchange and get the price data
        for exchange in exchanges_to_try:
            price_params = {"auth": "", "excd": exchange, "symb": ticker}
            raw_data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "price", price_params)
            data_content = raw_data[0] # Get the actual data from the tuple
            if isinstance(data_content, list) and len(data_content) > 0 and data_content[0].get("last"):
                price_data = data_content
                found_exchange = exchange
                break
        
        # If not found on any exchange, return a default response
        if not price_data:
            return {"name": ticker, "price": 0, "diff": 0, "rate": 0, "volume": 0, "open": 0, "high": 0, "low": 0}

        # Now, get the daily data using the found exchange
        today = datetime.now()
        inqr_end_dt = today.strftime("%Y%m%d")
        daily_params = {
            "auth": "",
            "excd": found_exchange,
            "symb": ticker,
            "gubn": "0", # Daily
            "bymd": inqr_end_dt,
            "modp": "0",
            "env_dv": "real"
        }
        daily_data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "dailyprice", daily_params)

        # Process price_data
        output = price_data[0]
        
        # Process daily_data to get high and low
        high_price = 0.0
        low_price = 0.0
        ohlcv_data = daily_data[0].get("output2", [])
        if isinstance(ohlcv_data, list) and len(ohlcv_data) > 0:
            latest_ohlcv = ohlcv_data[0]
            high_price = safe_float(latest_ohlcv.get("high"))
            low_price = safe_float(latest_ohlcv.get("low"))

        return {
            "name": ticker, 
            "price": safe_float(output.get("last")), 
            "diff": safe_float(output.get("diff")), 
            "rate": safe_float(output.get("rate")), 
            "volume": safe_int(output.get("tvol")), 
            "open": safe_float(output.get("base")), 
            "high": high_price, 
            "low": low_price
        }
    else: # Domestic
        price_params = {"env_dv": "real", "fid_cond_mrkt_div_code": "J", "fid_input_iscd": ticker}
        info_params = {"prdt_type_cd": "300", "pdno": ticker} # Added prdt_type_cd

        # Using asyncio.gather for concurrent calls
        price_raw_result, info_raw_result = await asyncio.gather(
            call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_price", price_params),
            call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "search_stock_info", info_params)
        )
        
        # Unpack the actual data from the tuples returned by call_mcp_tool
        price_data_content = price_raw_result[0]
        info_data_content = info_raw_result[0]

        price_data = {}
        if isinstance(price_data_content, list) and len(price_data_content) > 0:
            price_data = price_data_content[0] # Assume the first item in the list is the price dict
        elif isinstance(price_data_content, dict):
            price_data = price_data_content.get("output", {}) # inquire_price wraps in "output"

        info_data = {}
        if isinstance(info_data_content, list) and len(info_data_content) > 0:
            info_data = info_data_content[0] # Assume the first item in the list is the info dict
        elif isinstance(info_data_content, dict):
            info_data = info_data_content # search_stock_info returns the dict directly

        stock_name = info_data.get("prdt_abrv_name", ticker) if info_data else ticker

        return {
            "name": stock_name,
            "price": safe_float(price_data.get("stck_prpr")),
            "diff": safe_float(price_data.get("stck_prdy_diff")),
            "rate": safe_float(price_data.get("prdy_ctrt")),
            "volume": safe_int(price_data.get("acml_vol")),
            "open": safe_float(price_data.get("stck_oprc")),
            "high": safe_float(price_data.get("stck_hgpr")),
            "low": safe_float(price_data.get("stck_lwpr"))
        }

@app.get("/ranking/charts")
async def get_ranking_charts():
    # The get_ranked_stocks function in ranking_chart_service already handles fetching from multiple exchanges and sorting.
    # It also returns the data in the format expected by the frontend.
    ranked_stocks = await get_ranked_stocks()
    return ranked_stocks

@app.get("/screener/us-market-cap-ranking")
async def get_us_market_cap_ranking():
    unique_stocks_map: Dict[str, Dict[str, Any]] = {}
    for excd in ["NYS", "NAS", "AMS"]:
        logging.warning(f"Fetching market cap ranking from exchange: {excd} using inquire_search")
        params = {
            "auth": "",
            "excd": excd,
            "co_yn_pricecur": "0", "co_st_pricecur": None, "co_en_pricecur": None,
            "co_yn_rate": "0", "co_st_rate": None, "co_en_rate": None,
            "co_yn_valx": "1", # Enable market cap filtering
            "co_st_valx": "500000000", # Start market cap (500 billion USD, in thousands)
            "co_en_valx": "9999999999999", # End market cap (a very large number)
            "co_yn_shar": "0", "co_st_shar": None, "co_en_shar": None,
            "co_yn_volume": "0", "co_st_volume": None, "co_en_volume": None,
            "co_yn_amt": "0", "co_st_amt": None, "co_en_amt": None,
            "co_yn_eps": "0", "co_st_eps": None, "co_en_eps": None,
            "co_yn_per": "0", "co_st_per": None, "co_en_per": None,
            "keyb": ""
        }
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_search", params)
        if data[0] and data[0].get("output2"):
            items_found_for_exchange = 0
            for item in data[0]["output2"]:
                ticker = item.get("symb", "")
                if ticker:
                    # The 'valx' field from inquire_search is market cap in thousands
                    item['market_cap'] = safe_float(item.get('valx', 0)) * 1000 # Convert to actual value
                    unique_stocks_map[ticker] = item # Use ticker as key to ensure uniqueness
                    items_found_for_exchange += 1
            logging.warning(f"Found {items_found_for_exchange} items from {excd}. Current unique map size: {len(unique_stocks_map)}")
    
    all_stocks = list(unique_stocks_map.values())
    # Sort by market_cap in descending order
    sorted_stocks = sorted(all_stocks, key=lambda x: x.get('market_cap', 0), reverse=True)
    logging.warning(f"Final unique stocks for market cap ranking: {len(sorted_stocks)} items.")
    return sorted_stocks

@app.get("/check_mcp_connectivity")
async def check_mcp_connectivity():
    """
    Checks connectivity to the MCP stock and pension servers.
    """
    results = {}

    # Check stock MCP server
    try:
        async with Client(f"{MCP_STOCK_SERVER_URL}/sse") as client:
            # Attempt to make a dummy call or just connect
            # A simple connection attempt is enough to check if the server is reachable
            results["stock_mcp_connectivity"] = "Connected"
    except Exception as e:
        results["stock_mcp_connectivity"] = f"Failed to connect: {e}"
        logging.error(f"Stock MCP connectivity check failed: {e}")

    # Check pension MCP server
    try:
        async with Client(f"{MCP_PENSION_SERVER_URL}/sse") as client:
            results["pension_mcp_connectivity"] = "Connected"
    except Exception as e:
        results["pcp_mcp_connectivity"] = f"Failed to connect: {e}"
        logging.error(f"Pension MCP connectivity check failed: {e}")

    return results