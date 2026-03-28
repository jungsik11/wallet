import os
import traceback
from typing import Any

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pykis import PyKis

# Load environment variables from .env file
load_dotenv()

# Initialize FastAPI app
app = FastAPI(title="KIS Stock Test API")

# Initialize PyKis client
try:
    kis = PyKis(
        id=os.getenv("KIS_ID"),
        account=os.getenv("KIS_ACNT"),
        appkey=os.getenv("KIS_APPKEY"),
        secretkey=os.getenv("KIS_SECRET"),
        keep_token=True,
    )
except Exception as e:
    print(f"Error initializing PyKis: {e}")
    kis = None

@app.get("/test_kis_stock/{ticker}")
async def test_kis_stock(ticker: str) -> dict[str, Any]:
    try:
        if not kis:
            raise HTTPException(status_code=500, detail="KIS client not initialized.")

        results: dict[str, Any] = {}

        # Test 1: Call without market parameter
        try:
            stock_no_market = kis.stock(ticker)
            results["no_market"] = {
                "success": True,
                "name": stock_no_market.name,
                "market": stock_no_market.market,
                "type": str(type(stock_no_market))
            }
        except Exception as e:
            results["no_market"] = {"success": False, "error": str(e)}

        # Test 2: Call with market='KRX' if 6-digit
        if ticker.isdigit() and len(ticker) == 6:
            try:
                stock_krx_market = kis.stock(ticker, market='KRX')
                results["krx_market"] = {
                    "success": True,
                    "name": stock_krx_market.name,
                    "market": stock_krx_market.market,
                    "type": str(type(stock_krx_market))
                }
            except Exception as e:
                results["krx_market"] = {"success": False, "error": str(e)}
        
        return results

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
