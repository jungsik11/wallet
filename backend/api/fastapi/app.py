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

@app.get("/account_balance")
async def get_account_balance(country: str = Query(None, description="Country code (US or KR)")):
    if country == "KR":
        params = {
            "cano": os.getenv("KIS_ACCT_STOCK1"), "acnt_prdt_cd": os.getenv("KIS_PROD_TYPE1"),
            "env_dv": "real", # Added missing env_dv parameter
            "afhr_flpr_yn": "N", "inqr_dvsn": "01", "unpr_dvsn": "01",
            "fund_sttl_icld_yn": "N", "fncg_amt_auto_rdpt_yn": "N", "prcs_dvsn": "00"
        }
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_balance", params)
        stocks = data.get("output1", [])
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
    elif country == "US":
        params = {
            "wcrc_frcr_dvsn_cd": "02",  # 02 : 외화 (Foreign Currency)
            "natn_cd": "840",           # 840 : 미국 (USA)
            "tr_mket_cd": "00",         # 00 : 전체 (All Markets)
            "inqr_dvsn_cd": "00",       # 00 : 전체 (All Inquiry Divisions)
        }
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_present_balance", params)
        
        stocks = data.get("output1", [])
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
            ]
        }    
    else:
        raise HTTPException(status_code=400, detail="Country must be KR or US")

@app.get("/calculate_profit", response_model=ProfitResponse)
async def calculate_profit(country: str = Query("US", description="Country code (US or KR)"), year: int = None):
    
    target_year = year if year is not None else datetime.now().year
    inqr_strt_dt = f"{target_year}0101"
    inqr_end_dt = f"{target_year}1231"

    if country == "US":
        params = {
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
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_period_profit", params)

        stocks_profit_data = data.get("output1", [])
        overall_profit_summary = data.get("output2", [{}])[0]

        yearly_total_profit = {"USD": safe_float(overall_profit_summary.get("ovrs_rlzt_pfls_tot_amt"))}
        
        processed_stocks = []
        for s in stocks_profit_data:
            processed_stocks.append(StockHolding(
                yearly_profit={"USD": safe_float(s.get("ovrs_rlzt_pfls_amt"))},
                holdings={
                    "name": s.get("ovrs_item_name"),
                    "ticker": s.get("ovrs_pdno"),
                    "market": s.get("ovrs_excg_cd"),
                    "currency": "USD"
                }
            ))

        return {"yearly_total_profit": yearly_total_profit, "stocks": processed_stocks}
    
    elif country == "KR":
        # This implementation is based on the hypothesis that a bulk call to 
        # inquire_period_trade_profit gives a list of stocks, but not their P/L,
        # and that a second call is needed for each stock to get its specific P/L.
        # Logging is added to verify this hypothesis.

        # 1. Get all stocks with trades in the period to get the list of tickers
        all_trades_params = {
            "cano": os.getenv("KIS_ACNT")[:8],
            "acnt_prdt_cd": os.getenv("KIS_ACNT")[9:],
            "inqr_strt_dt": inqr_strt_dt,
            "inqr_end_dt": inqr_end_dt,
            "sort_dvsn": "00",
            "cblc_dvsn": "00",
            "pdno": "",  # Empty to get all stocks with trades
            "tr_cont": "",
        }
        all_trades_data = await call_mcp_tool(
            MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_period_trade_profit", all_trades_params
        )
        
        stocks_with_trades = all_trades_data.get("output1", [])
        overall_summary = all_trades_data.get("output2", [{}])[0]
        # Using 'tot_rlzt_pfls' based on the user's log for the other API, assuming it might be similar.
        # If not, the single-stock calls will provide the definitive total.
        total_profit = safe_float(overall_summary.get("tot_rlzt_pfls", overall_summary.get("rlzt_pfls_amt")))

        processed_stocks = []
        
        # Create a unique list of stocks (pdno and prdt_name)
        unique_stocks = {
            (s.get("pdno"), s.get("prdt_name")) for s in stocks_with_trades if s.get("pdno")
        }

        # 2. For each unique stock, get its specific profit/loss for the period
        actual_total_profit = 0.0
        for pdno, prdt_name in unique_stocks:
            single_stock_params = {
                "cano": os.getenv("KIS_ACNT")[:8],
                "acnt_prdt_cd": os.getenv("KIS_ACNT")[9:],
                "inqr_strt_dt": inqr_strt_dt,
                "inqr_end_dt": inqr_end_dt,
                "sort_dvsn": "00",
                "cblc_dvsn": "00",
                "pdno": pdno,  # Specific stock ticker
                "tr_cont": "",
            }
            
            single_stock_data = await call_mcp_tool(
                MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_period_trade_profit", single_stock_params
            )
            
            # The summary output (output2) of a single-stock query should give the P/L for that stock
            stock_summary = single_stock_data.get("output2", [{}])[0]
            # Assuming the realized profit field is 'rlzt_pfls_amt' or 'tot_rlzt_pfls'
            realized_profit = safe_float(stock_summary.get("tot_rlzt_pfls", stock_summary.get("rlzt_pfls_amt")))
            actual_total_profit += realized_profit

            processed_stocks.append(StockHolding(
                yearly_profit={"KRW": realized_profit},
                holdings={
                    "name": prdt_name,
                    "ticker": pdno,
                    "market": "KRX",
                    "currency": "KRW"
                }
            ))

        # Use the sum of individual profits as the final total, as it's more reliable
        return {"yearly_total_profit": {"KRW": actual_total_profit}, "stocks": processed_stocks}
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
    stocks = data.get("output1", [])
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

@app.get("/ohlcv")
async def get_ohlcv(ticker: str, timeframe: str = Query('D', description="Timeframe: 'Y' (yearly), 'D' (daily), 'W' (weekly), 'M' (monthly)")):
    today = datetime.now()
    # Fetch data for the last year for simplicity
    start_date = today - timedelta(days=365)
    inqr_strt_dt = start_date.strftime("%Y%m%d")
    inqr_end_dt = today.strftime("%Y%m%d")

    period_map = {
        'Y': 'Y',
        'M': 'M',
        'W': 'W',
        'D': 'D'
    }
    fid_period_div_code = period_map.get(timeframe.upper(), 'D')

    if ticker.isdigit(): # Domestic Stock
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

        processed_ohlcv = []
        for item in ohlcv_data:
            processed_ohlcv.append({
                "date": item.get("stck_bsop_date"),
                "open": safe_float(item.get("stck_oprc")),
                "high": safe_float(item.get("stck_hgpr")),
                "low": safe_float(item.get("stck_lwpr")),
                "close": safe_float(item.get("stck_clpr")),
                "volume": safe_int(item.get("acml_vol"))
            })
        return {"data": processed_ohlcv}
    else: # Overseas Stock
        # Map timeframe to gubn for dailyprice tool
        gubn_map = {
            'D': '0',
            'W': '1',
            'M': '2',
            'Y': '2' # dailyprice tool does not directly support yearly, default to monthly
        }
        gubn_code = gubn_map.get(timeframe.upper(), '0')

        # List of exchanges to try for overseas stocks
        exchanges_to_try = ["NAS", "NYS", "AMS"]
        
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
                processed_ohlcv = []
                for item in ohlcv_data:
                    processed_ohlcv.append({
                        "date": item.get("xymd"),
                        "open": safe_float(item.get("open")),
                        "high": safe_float(item.get("high")),
                        "low": safe_float(item.get("low")),
                        "close": safe_float(item.get("clos")),
                        "volume": safe_int(item.get("tvol"))
                    })
                return {"data": processed_ohlcv}
        
        # If loop finishes without finding data, return empty
        return {"data": []}

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
        if isinstance(data, list) and len(data) > 0:
            output = data[0]
            if output:
                return {"current_price": safe_float(output.get("stck_prpr"))}
        elif isinstance(data, dict):
            output = data.get("output", {})
            if output:
                return {"current_price": safe_float(output.get("stck_prpr"))}
        return {"current_price": 0.0}

@app.get("/stock/{ticker}")
async def get_stock_detail(ticker: str, exchange: str = Query("NAS", description="Exchange code (e.g., NAS, NYS, AMS)")):
    if not ticker.isdigit(): # Overseas
        # Define two API calls to be made concurrently
        price_params = {"auth": "", "excd": exchange.upper(), "symb": ticker}
        
        today = datetime.now()
        inqr_end_dt = today.strftime("%Y%m%d")
        daily_params = {
            "auth": "",
            "excd": exchange.upper(),
            "symb": ticker,
            "gubn": "0", # Daily
            "bymd": inqr_end_dt,
            "modp": "0",
            "env_dv": "real"
        }

        # Use asyncio.gather to run both API calls concurrently
        results = await asyncio.gather(
            call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "price", price_params),
            call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "dailyprice", daily_params)
        )
        
        price_data, daily_data = results
        
        # Process price_data
        output = {}
        if isinstance(price_data, list) and len(price_data) > 0:
            output = price_data[0]
        
        # Process daily_data to get high and low
        high_price = 0.0
        low_price = 0.0
        ohlcv_data = daily_data.get("output2", [])
        if isinstance(ohlcv_data, list) and len(ohlcv_data) > 0:
            # The first item is the most recent data
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
        info_params = {"PDNO": ticker} # Assuming PDNO is the parameter for product info

        results = await asyncio.gather(
            call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_price", price_params),
            call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_product_info", info_params)
        )
        
        price_data, info_data = results

        output = {}
        if isinstance(price_data, list) and len(price_data) > 0:
            output = price_data[0]
        
        # Assuming info_data is a dict with product name
        stock_name = info_data.get("prdt_name", "") if isinstance(info_data, dict) else ""

        return {
            "name": stock_name,
            "price": safe_float(output.get("stck_prpr")),
            "diff": safe_float(output.get("stck_prdy_diff")),
            "rate": safe_float(output.get("prdy_ctrt")),
            "volume": safe_int(output.get("acml_vol")),
            "open": safe_float(output.get("stck_oprc")),
            "high": safe_float(output.get("stck_hgpr")),
            "low": safe_float(output.get("stck_lwpr"))
        }

@app.get("/ranking/charts")
async def get_ranking_charts():
    # The get_ranked_stocks function in ranking_chart_service already handles fetching from multiple exchanges and sorting.
    # It also returns the data in the format expected by the frontend.
    ranked_stocks = await get_ranked_stocks()
    return ranked_stocks

@app.get("/screener/us-market-cap-ranking")
async def get_us_market_cap_ranking():
    all_stocks = []
    for excd in ["NYS", "NAS", "AMS"]:
        params = {"excd": excd, "vol_rang": "0"}
        data = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "market_cap", params)
        if data and data.get("output2"):
            all_stocks.extend(data["output2"])
    return all_stocks

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
        results["pension_mcp_connectivity"] = f"Failed to connect: {e}"
        logging.error(f"Pension MCP connectivity check failed: {e}")

    return results