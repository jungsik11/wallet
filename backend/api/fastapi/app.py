import os
import traceback
import logging
import asyncio
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional

import pandas as pd
import numpy as np
import yfinance as yf
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from dotenv import load_dotenv
from fastmcp import Client
import FinanceDataReader as fdr

from ranking_chart_service import get_ranked_stocks
from utils import call_mcp_tool, MCP_STOCK_SERVER_URL, MCP_PENSION_SERVER_URL, StockHolding, ProfitResponse
from ra.mpt import ModernPortfolioTheory
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

async def get_kr_risk_free_rate() -> float:
    """
    Fetches the current Korean 3-Year Treasury Bond yield.
    Fallback to 3.59% as of March 2026 if live data is unavailable.
    """
    # 3.59% is the recent yield for KR 3Y Treasury Bond as of March 2026
    fallback_rate = 0.0359
    
    try:
        # Tickers for KR 3Y Bond yield often change or are blocked
        # KR3YT=RR (Yahoo), KRDR1Y3 (BOK), etc.
        for code in ['KR3YT=RR', 'KRDR1Y3', '010170000']:
            try:
                df = fdr.DataReader(code)
                if df is not None and not df.empty:
                    # Some sources return yield as percentage (e.g., 3.59)
                    latest_yield = float(df.iloc[-1]['Close'])
                    if latest_yield > 10: # Likely basis points
                        return latest_yield / 10000.0
                    elif latest_yield > 0.1: # Likely percentage
                        return latest_yield / 100.0
                    return latest_yield
            except Exception as e:
                logging.warning(f"Failed to fetch KR bond yield for code {code}: {e}")
                continue

        logging.warning(f"All KR bond yield fetch attempts failed. Using fallback: {fallback_rate * 100}%")
        return fallback_rate
    except Exception as e:
        logging.error(f"Unexpected error in get_kr_risk_free_rate: {e}")
        return fallback_rate



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
            "env_dv": "real",
            "afhr_flpr_yn": "N", "inqr_dvsn": "02", "unpr_dvsn": "01",
            "fund_sttl_icld_yn": "N", "fncg_amt_auto_rdpt_yn": "N", "prcs_dvsn": "00"
        }
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_balance", params)
        
        # FIX: data is a dict, not a list
        stocks = data.get("output1", [])
        summary = {}
        if data.get("output2"):
            summary = data.get("output2", [{}])[0]

        # Calculate settled cash
        evlu_amt_smtl = safe_int(summary.get("evlu_amt_smtl_amt"))
        tot_evlu_amt = safe_int(summary.get("tot_evlu_amt"))
        settled_cash = tot_evlu_amt - evlu_amt_smtl

        return {
            "cash": {
                "krw": safe_int(summary.get("dnca_tot_amt")), # 예수금
                "settled_krw": settled_cash
            },
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
            "wcrc_frcr_dvsn_cd": "02",
            "natn_cd": "840",
            "tr_mket_cd": "00",
            "inqr_dvsn_cd": "00",
        }
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_present_balance", params)
        
        # FIX: data is a dict, not a list
        stocks = data.get("output1", [])
        summary_output2 = {}
        if data.get("output2"):
            summary_output2 = data.get("output2", [{}])[0]

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
            "exchange_rate": safe_float(summary_output2.get('frst_bltn_exrt', 0 ))
        }    
    else:
        raise HTTPException(status_code=400, detail="Country must be KR or US")

@app.get("/calculate_profit")
async def calculate_profit(country: str = Query(..., description="Country code (US or KR)"), year: int = Query(..., description="Year for profit calculation (e.g., 2021)")):
    
    inqr_strt_dt = f"{year}0101"
    inqr_end_dt = f"{year}1231"

    if country == "US":
        us_params = {
            "cano": os.getenv("KIS_ACCT_STOCK1"),
            "acnt_prdt_cd": os.getenv("KIS_PROD_TYPE1"),
            "ovrs_excg_cd": "NASD",
            "natn_cd": "",
            "crcy_cd": "USD",
            "pdno": "",
            "inqr_strt_dt": inqr_strt_dt,
            "inqr_end_dt": inqr_end_dt,
            "wcrc_frcr_dvsn_cd": "01",
            "FK200": "",
            "NK200": "",
        }
        us_data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_period_profit", us_params)

        us_stocks_profit_data = us_data.get("output1", [])
        us_overall_profit_summary = {}
        if us_data.get("output2"):
            us_overall_profit_summary = us_data.get("output2", [{}])[0]

        total_usd_profit_for_year = safe_float(us_overall_profit_summary.get("ovrs_rlzt_pfls_tot_amt"))
        
        all_processed_stocks_usd: Dict[str, Dict[str, Any]] = {}
        for s in us_stocks_profit_data:
            ticker = s.get("ovrs_pdno")
            if ticker not in all_processed_stocks_usd:
                all_processed_stocks_usd[ticker] = {
                    "name": s.get("ovrs_item_name"),
                    "ticker": ticker,
                    "market": s.get("ovrs_excg_cd"),
                    "currency": "USD",
                    "yearly_profit_usd": 0.0
                }
            stock_usd_profit = safe_float(s.get("ovrs_rlzt_pfls_amt"))
            all_processed_stocks_usd[ticker]["yearly_profit_usd"] += stock_usd_profit
        
        final_stocks_output_usd = []
        for ticker, details in all_processed_stocks_usd.items():
            final_stocks_output_usd.append(StockHolding(
                yearly_profit={"USD": details["yearly_profit_usd"]},
                holdings={
                    "name": details["name"],
                    "ticker": details["ticker"],
                    "market": details["market"],
                    "currency": details["currency"]
                }
            ))
        
        return {"yearly_profit_usd": total_usd_profit_for_year, "stocks": final_stocks_output_usd}

    elif country == "KR":
        kr_all_trades_params = {
            "cano": os.getenv("KIS_ACCT_STOCK1"),
            "acnt_prdt_cd": os.getenv("KIS_PROD_TYPE1"),
            "inqr_strt_dt": inqr_strt_dt,
            "inqr_end_dt": inqr_end_dt,
            "sort_dvsn": "00",
            "cblc_dvsn": "00",
            "pdno": "",
            "tr_cont": "",
        }
        kr_all_trades_data = await call_mcp_tool(
            MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_period_trade_profit", kr_all_trades_params
        )
        
        kr_stocks_with_trades = kr_all_trades_data.get("output1", [])
        kr_overall_summary = {}
        if kr_all_trades_data.get("output2"):
            kr_overall_summary = kr_all_trades_data.get("output2", [{}])[0]
        
        total_krw_profit_for_year = safe_float(kr_overall_summary.get("tot_rlzt_pfls", kr_overall_summary.get("rlzt_pfls_amt")))
        
        all_processed_stocks_krw: Dict[str, Dict[str, Any]] = {}

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
                yearly_profit={"KRW": details["yearly_profit_krw"]},
                holdings={
                    "name": details["name"],
                    "ticker": details["ticker"],
                    "market": details["market"],
                    "currency": details["currency"]
                }
            ))
        return {"yearly_profit_krw": total_krw_profit_for_year, "stocks": final_stocks_output_krw}
    
    else:
        raise HTTPException(status_code=400, detail="Country must be US or KR")

@app.get("/account_balance_pension")
async def get_account_balance_pension():
    params = {
            "cano": os.getenv("KIS_ACCT_STOCK2"), "acnt_prdt_cd": os.getenv("KIS_PROD_TYPE2"),
            "env_dv": "real",
            "afhr_flpr_yn": "N", "inqr_dvsn": "02", "unpr_dvsn": "01",
            "fund_sttl_icld_yn": "N", "fncg_amt_auto_rdpt_yn": "N", "prcs_dvsn": "00"
        }
    data = await call_mcp_tool(MCP_PENSION_SERVER_URL, "domestic_stock", "inquire_balance", params)
    
    # FIX: data is a dict, not a list
    stocks = data.get("output1", [])
    summary = {}
    if data.get("output2"):
        summary = data.get("output2", [{}])[0]
    
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

    # Initialize end_dt as a datetime object for minute/hour calculations
    try:
        end_dt = datetime.strptime(inqr_end_dt, "%Y%m%d")
    except ValueError:
        end_dt = today # Fallback if parsing fails

    if timeframe == 'Y':
        start_date = datetime(today.year - 20, 1, 1) # Go back 20 years for yearly
        inqr_strt_dt = start_date.strftime("%Y%m%d")
    elif timeframe == 'M':
        start_date = today - timedelta(days=365 * 5) # Go back 5 years for monthly
        inqr_strt_dt = start_date.strftime("%Y%m%d")
    elif timeframe == 'D':
        start_date = today - timedelta(days=365) # Go back 1 year for daily
        inqr_strt_dt = start_date.strftime("%Y%m%d")
    elif timeframe == 'T': # Minute data
        # For domestic minute data, KIS API 'inquire_time_itemchartprice' is for a single day.
        # We will use inqr_end_dt (which defaults to today) as the target date for minute data.
        pass
    elif timeframe == 'H': # Hourly data
        # For domestic hourly data, we will aggregate minute data for a single day (inqr_end_dt).
        pass
    else:
        raise HTTPException(status_code=400, detail="Invalid timeframe. Choose from Y, M, D, T, H.")

    processed_ohlcv = []
    message = "OHLCV data fetched successfully."

    if ticker.isdigit(): # Domestic Stock
        if timeframe == 'H': # Hourly data for domestic
            target_date_str = end_dt.strftime("%Y%m%d")
            
            minute_data = await call_mcp_tool(
                MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_time_dailychartprice", # API 변경
                {
                    "fid_cond_mrkt_div_code": "J",
                    "fid_input_iscd": ticker,
                    "fid_input_hour_1": "090000", # 오전 9시부터 데이터를 요청
                    "fid_input_date_1": target_date_str, # 날짜 파라미터 추가
                    "fid_pw_data_incu_yn": "N",
                    # "fid_etc_cls_code": "", # 이 파라미터는 inquire_time_dailychartprice에서 사용되지 않음
                }
            )
            print(f"Raw minute data from KIS for ticker {ticker} on {target_date_str}: {minute_data}")
            minute_data_for_day = minute_data.get("output2", [])
            
            hourly_candles: Dict[datetime, Dict[str, Any]] = {}
            for item in minute_data_for_day:
                cntg_hour_str = item.get("stck_cntg_hour")
                # Use actual OHLC values from minute data
                minute_open = safe_float(item.get("stck_oprc"))
                minute_high = safe_float(item.get("stck_hgpr"))
                minute_low = safe_float(item.get("stck_lwpr"))
                minute_close = safe_float(item.get("stck_prpr")) # Use stck_prpr as the minute's closing price
                trade_volume = safe_int(item.get("cntg_vol"))

                if not cntg_hour_str:
                    continue

                current_candle_dt = datetime.strptime(f"{target_date_str}{cntg_hour_str}", "%Y%m%d%H%M%S")

                hour_start = current_candle_dt.replace(minute=0, second=0, microsecond=0)

                if hour_start not in hourly_candles:
                    hourly_candles[hour_start] = {
                        "date": hour_start.isoformat(timespec='seconds'),
                        "open": minute_open, # Use the actual open of the first minute in this hour
                        "high": minute_high,
                        "low": minute_low,
                        "close": minute_close,
                        "volume": trade_volume
                    }
                else:
                    hourly_candles[hour_start]["high"] = max(hourly_candles[hour_start]["high"], minute_high) # Use minute_high
                    hourly_candles[hour_start]["low"] = min(hourly_candles[hour_start]["low"], minute_low)   # Use minute_low
                    hourly_candles[hour_start]["close"] = minute_close # Last minute's close is hourly close
                    hourly_candles[hour_start]["volume"] += trade_volume
            
            processed_ohlcv = sorted(hourly_candles.values(), key=lambda x: x['date'])
            message = f"Domestic hourly OHLCV data for {target_date_str} fetched and aggregated successfully."

        elif timeframe == 'T': # Minute data for domestic
            target_date_str = end_dt.strftime("%Y%m%d")
            params = {
                "env_dv": "real", # `inquire_time_itemchartprice`는 이 파라미터를 받음
                "fid_cond_mrkt_div_code": "J", # Always KRX for domestic stocks
                "fid_input_iscd": ticker,
                "fid_input_hour_1": "000000",  # Start from midnight to get all minute data for the day
                "fid_pw_data_incu_yn": "N",  # Do not include past data (as we are querying for a specific day)
                "fid_etc_cls_code": "", # `inquire_time_itemchartprice`는 이 파라미터를 받음
            }

            data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_time_itemchartprice", params) # API 복구
            ohlcv_data = data.get("output2", [])

            if isinstance(ohlcv_data, list):
                for item in ohlcv_data:
                    if isinstance(item, dict):
                        cntg_hour = item.get("stck_cntg_hour")
                        if cntg_hour:
                            dt_str = f"{target_date_str[:4]}-{target_date_str[4:6]}-{target_date_str[6:8]}T{cntg_hour[:2]}:{cntg_hour[2:4]}:{cntg_hour[4:6]}"
                            trade_price = safe_float(item.get("stck_prpr"))
                            trade_volume = safe_int(item.get("cntg_vol"))

                            processed_ohlcv.append({
                                "date": dt_str,
                                "open": safe_float(item.get("stck_oprc")),
                                "high": safe_float(item.get("stck_hgpr")),
                                "low": safe_float(item.get("stck_lwpr")),
                                "close": safe_float(item.get("stck_prpr")),
                                "volume": trade_volume
                            })
            processed_ohlcv.sort(key=lambda x: x.get('date'))
            message = f"Domestic minute OHLCV data for {target_date_str} fetched successfully."
            
        else: # Daily, Weekly, Monthly, Yearly for domestic
            period_map = {
                'Y': 'Y', 'M': 'M', 'W': 'W', 'D': 'D'
            }
            fid_period_div_code = period_map.get(timeframe, 'D')

            params = {
                "env_dv": "real",
                "fid_cond_mrkt_div_code": "J",
                "fid_input_iscd": ticker,
                "fid_input_date_1": inqr_strt_dt,
                "fid_input_date_2": inqr_end_dt,
                "fid_period_div_code": fid_period_div_code,
                "fid_org_adj_prc": "0"
            }
            data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_daily_itemchartprice", params)
            ohlcv_data = data.get("output2", [])

            current_calendar_year = today.year
            for item in ohlcv_data:
                item_date_str = item.get("stck_bsop_date")
                year_of_data = int(item_date_str[:4])
                
                if timeframe == 'Y' and year_of_data < current_calendar_year:
                    formatted_date = f"{year_of_data}-12-31"
                elif timeframe == 'Y' and year_of_data == current_calendar_year:
                    formatted_date = today.strftime("%Y-%m-%d")
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
            ohlcv_data = data.get("output2", [])

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
                
                if data and data.get("output2"):
                    monthly_ohlcv_data = data["output2"]
                    found_exchange = exchange
                    break
            
            if not monthly_ohlcv_data:
                message = f"Could not fetch monthly data for overseas stock '{ticker}' from any exchange. Yearly OHLCV cannot be generated."
            else:
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
        
        elif timeframe == 'H': # Hourly data for overseas
            all_ohlcv_data = []
            for exchange in ["NYS", "NAS", "AMS"]:
                params = {"auth": "", "excd": exchange, "symb": ticker, "nmin": "60", "pinc": "1", "next": "", "nrec": "120", "fill": "", "keyb": ""}
                data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_time_itemchartprice", params)
                page_data = data.get("output2", [])
                if page_data:
                    all_ohlcv_data = page_data
                    found_exchange = exchange
                    break
            
            if all_ohlcv_data and safe_float(all_ohlcv_data[0].get("open")) == 0:
                message = f"Overseas hourly OHLCV data for '{ticker}' is empty or invalid from {found_exchange}."
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
                message = f"Hourly OHLCV data for overseas stock fetched successfully from {found_exchange}."

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
                ohlcv_data = data.get("output2", [])

                if ohlcv_data: # If data is found, process and return it
                    for item in ohlcv_data:
                        item_date_str = item.get("xymd")
                        formatted_date = f"{item_date_str[:4]}-{item_date_str[4:6]}-{item_date_str[6:8]}"
                        processed_ohlcv.append({
                            "date": formatted_date,
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
                page_data = data.get("output2", []) # data is a tuple (output, message)
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
            price_data = data.get("output1", [])
            if price_data and isinstance(price_data, list) and price_data[0].get("last"):
                return {"current_price": safe_float(price_data[0].get("last"))}
        return {"current_price": 0.0}
    else: # Domestic
        params = {"env_dv": "real", "fid_cond_mrkt_div_code": "J", "fid_input_iscd": ticker}
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_price", params)
        output = data.get("output", {})
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
            if isinstance(raw_data, list) and len(raw_data) > 0 and raw_data[0] and raw_data[0].get("last"):
                price_data = raw_data
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
        ohlcv_data = daily_data.get("output2", [])
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
        
        # Defensively extract price_data
        price_data = {}
        
        # Determine the effective data source from price_raw_result
        # This handles cases where price_raw_result is a dict (expected after utils.py fix)
        # or a list (if utils.py fix is not active, or MCP returns a bare list directly)
        effective_data_source = None

        if isinstance(price_raw_result, dict):
            # If it's a dict, check for 'output' or 'data_list' keys
            if "output" in price_raw_result:
                effective_data_source = price_raw_result["output"]
            elif "data_list" in price_raw_result: # This would be from utils.py fix
                effective_data_source = price_raw_result["data_list"]
        elif isinstance(price_raw_result, list):
            # If price_raw_result itself is a list (utils.py fix not active or bare list from MCP)
            effective_data_source = price_raw_result

        # Process the determined data source
        if effective_data_source:
            if isinstance(effective_data_source, list) and effective_data_source:
                # Assuming the first item in the list is the relevant stock price data dictionary
                if isinstance(effective_data_source[0], dict):
                    price_data = effective_data_source[0]
                else:
                    logging.warning(f"Effective data source is a list but its first item is not a dictionary: {effective_data_source}")
            elif isinstance(effective_data_source, dict):
                price_data = effective_data_source
            else:
                logging.warning(f"Effective data source is neither a dictionary nor a list as expected: {effective_data_source}")
        else:
            logging.warning(f"Could not determine effective data source from price_raw_result: {price_raw_result}")
            
        # If price_data is still empty, it means we couldn't parse the data as expected
        if not price_data:
             raise HTTPException(status_code=500, detail="Failed to parse price data from API response or response was empty.")
        
        # Defensively extract info_data
        info_data = {}
        effective_info_source = None

        if isinstance(info_raw_result, dict):
            if "output" in info_raw_result:
                effective_info_source = info_raw_result["output"]
            elif "data_list" in info_raw_result:
                effective_info_source = info_raw_result["data_list"]
        elif isinstance(info_raw_result, list):
            effective_info_source = info_raw_result

        if effective_info_source:
            if isinstance(effective_info_source, list) and effective_info_source:
                if isinstance(effective_info_source[0], dict):
                    info_data = effective_info_source[0]
                else:
                    logging.warning(f"Effective info source is a list but its first item is not a dictionary: {effective_info_source}")
            elif isinstance(effective_info_source, dict):
                info_data = effective_info_source
            else:
                logging.warning(f"Effective info source is neither a dictionary nor a list as expected: {effective_info_source}")
        else:
            logging.warning(f"Could not determine effective info source from info_raw_result: {info_raw_result}")
            
        if not info_data:
            raise HTTPException(status_code=500, detail="Failed to parse info data from API response or response was empty.")

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
        if data and data.get("output2"):
            items_found_for_exchange = 0
            for item in data["output2"]:
                ticker = item.get("symb", "")
                if ticker:
                    # The 'valx' field from inquire_search is market cap in thousands
                    item['market_cap'] = safe_float(item.get('valx', 0)) * 1000 # Convert to actual value
                    unique_stocks_map[ticker] = item # Use ticker as key to ensure uniqueness
                    items_found_for_exchange += 1
    
    all_stocks = list(unique_stocks_map.values())
    # Sort by market_cap in descending order
    sorted_stocks = sorted(all_stocks, key=lambda x: x.get('market_cap', 0), reverse=True)
    return sorted_stocks

async def _perform_optimization(
    tickers: List[str],
    days: int = 365,
    risk_free_rate: Optional[float] = None
):
    """
    Internal helper to perform MPT optimization.
    """
    # Fetch risk-free rate if not provided
    used_rf_rate = risk_free_rate
    if used_rf_rate is None:
        used_rf_rate = await get_kr_risk_free_rate()
        logging.info(f"Automatically fetched KR Risk-Free Rate: {used_rf_rate}")

    # Use yesterday's close for stability throughout the day
    end_date = datetime.now() - timedelta(days=1)
    start_date = end_date - timedelta(days=days)
    
    # Download historical data
    logging.info(f"Fetching data for tickers: {tickers}")
    data_raw = yf.download(
        tickers, 
        start=start_date.strftime("%Y-%m-%d"), 
        end=end_date.strftime("%Y-%m-%d"), 
        threads=False
    )
    
    if data_raw.empty:
        raise HTTPException(status_code=404, detail="No historical data found for the given tickers and period.")
        
    # Extract closing prices
    if len(tickers) == 1:
        data = data_raw['Close'].to_frame()
    else:
        # Handle potential MultiIndex columns if multiple tickers are fetched
        if isinstance(data_raw.columns, pd.MultiIndex):
            data = data_raw['Close']
        else:
            data = data_raw['Close']
    
    # Drop columns with all NaNs and tickers with insufficient data
    data = data.dropna(axis=1, how='all')
    if data.empty:
        raise HTTPException(status_code=404, detail="Data found but all records are invalid (NaN).")

    # Calculate daily returns
    daily_returns = data.pct_change().dropna()
    if len(daily_returns) < 2:
        raise HTTPException(status_code=400, detail="Insufficient data points to calculate returns and covariance.")

    # Annualize expected returns (252 trading days)
    expected_returns = daily_returns.mean() * 252
    
    # Annualize covariance matrix
    cov_matrix = daily_returns.cov() * 252
    
    # Initialize MPT Optimizer
    mpt = ModernPortfolioTheory(expected_returns, cov_matrix)
    
    # Perform Optimizations
    sharpe_weights = mpt.optimize_max_sharpe(risk_free_rate=used_rf_rate)
    min_vol_weights = mpt.optimize_min_volatility()
    
    # Calculate metrics for Max Sharpe Portfolio
    sharpe_ret = mpt.get_portfolio_return(sharpe_weights.values)
    sharpe_vol = np.sqrt(mpt.get_portfolio_variance(sharpe_weights.values))
    sharpe_ratio = (sharpe_ret - used_rf_rate) / (sharpe_vol + 1e-9)
    
    # Calculate metrics for Min Volatility Portfolio
    min_vol_ret = mpt.get_portfolio_return(min_vol_weights.values)
    min_vol_vol = np.sqrt(mpt.get_portfolio_variance(min_vol_weights.values))
    min_vol_sharpe = (min_vol_ret - used_rf_rate) / (min_vol_vol + 1e-9)

    return {
        "max_sharpe": {
            "weights": sharpe_weights.to_dict(),
            "return": float(sharpe_ret),
            "volatility": float(sharpe_vol),
            "sharpe_ratio": float(sharpe_ratio)
        },
        "min_volatility": {
            "weights": min_vol_weights.to_dict(),
            "return": float(min_vol_ret),
            "volatility": float(min_vol_vol),
            "sharpe_ratio": float(min_vol_sharpe)
        },
        "risk_free_rate": used_rf_rate,
        "period": {
            "start": start_date.strftime("%Y-%m-%d"),
            "end": end_date.strftime("%Y-%m-%d"),
            "days": days
        }
    }

@app.get("/ra/optimize")
async def optimize_portfolio(
    tickers: List[str] = Query(..., description="List of tickers to optimize"),
    days: int = Query(365, description="Number of historical days to fetch"),
    risk_free_rate: Optional[float] = Query(None, description="Risk-free rate (decimal). If None, fetches KR 3Y Bond Yield.")
):
    """
    Optimizes a portfolio of given tickers using Modern Portfolio Theory (MPT).
    """
    try:
        return await _perform_optimization(tickers, days, risk_free_rate)
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error in /ra/optimize: {str(e)}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Optimization failed: {str(e)}")

@app.get("/ra/portfolio")
async def get_recommended_portfolio():
    """
    Returns a globally diversified recommended portfolio including KR ETFs.
    """
    # Define a mix of US stocks and KR ETFs
    # .KS suffix is used for KOSPI stocks/ETFs in yfinance
    default_tickers = [
        'AAPL', 'MSFT', 'NVDA', # US Tech
        '069500.KS', # KODEX 200 (KR Market)
        '133690.KS', # TIGER US Nasdaq 100 (Global Tech)
        '143850.KS', # TIGER US S&P 500 (US Market)
        '114260.KS', # KODEX KR Treasury Bond 3Y (KR Bond)
        '132030.KS', # KODEX Gold Futures (Commodity)
        '261240.KS'  # KODEX USD Futures (Currency)
    ]
    
    # Mapping for display names
    ticker_names = {
        'AAPL': 'Apple',
        'MSFT': 'Microsoft',
        'NVDA': 'NVIDIA',
        '069500.KS': 'KODEX 200 (국내주식)',
        '133690.KS': 'TIGER 미국나스닥100',
        '143850.KS': 'TIGER 미국S&P500',
        '114260.KS': 'KODEX 국고채3년 (국내채권)',
        '132030.KS': 'KODEX 골드선물',
        '261240.KS': 'KODEX 미국달러선물'
    }

    try:
        result = await _perform_optimization(default_tickers, days=365)
        
        # Replace ticker keys with friendly names in the weights
        for strategy in ['max_sharpe', 'min_volatility']:
            weights = result[strategy]['weights']
            new_weights = {}
            for ticker, weight in weights.items():
                name = ticker_names.get(ticker, ticker)
                new_weights[name] = weight
            result[strategy]['weights'] = new_weights
            
        return result
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error in /ra/portfolio: {str(e)}\n{traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Failed to load recommended portfolio: {str(e)}")



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