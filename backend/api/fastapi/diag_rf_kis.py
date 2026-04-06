import asyncio
import logging
import sys
import os

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import call_mcp_tool, MCP_STOCK_SERVER_URL

logging.basicConfig(level=logging.INFO)

async def test_rf_rate_kis():
    print("--- Testing KIS MCP for Risk-Free Rate (KORPT038) ---")
    params = {
        "fid_cond_mrkt_div_code": "U",  # Indicators/Indices
        "fid_input_iscd": "KORPT038",    # KTB 3Y Yield symbol
        "tr_cont": ""                   
    }
    try:
        # Try inquire_index_price
        print("[DEBUG] Trying inquire_index_price...")
        res = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_index_price", params)
        print(f"[DEBUG] Response: {res}")
        
        # Also try inquire_price (common alternative)
        print("\n[DEBUG] Trying inquire_price...")
        res2 = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_price", {"fid_cond_mrkt_div_code": "U", "fid_input_iscd": "KORPT038"})
        print(f"[DEBUG] Response: {res2}")

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    asyncio.run(test_rf_rate_kis())
