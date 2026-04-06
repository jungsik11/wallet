import asyncio
import os
import sys
import logging

# Ensure we can import from the current directory
sys.path.append(os.getcwd())

async def test_mcp():
    from utils import call_mcp_tool, MCP_STOCK_SERVER_URL
    print(f"--- Testing MCP Connection to {MCP_STOCK_SERVER_URL} ---")
    
    # Testing the daily index price which usually returns lists
    params = {
        "fid_cond_mrkt_div_code": "U",
        "fid_input_iscd": "KORPT038",
        "fid_period_div_code": "D",
        "fid_input_date_1": "20260402",
        "tr_cont": ""
    }
    
    print(f"\n--- Deep Inspection of KORPT038 via inquire_index_daily_price ---")
    try:
        res = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_index_daily_price", params)
        if isinstance(res, dict):
            # Many KIS tools return list in output2
            output_list = res.get('output2') or res.get('output') or []
            if isinstance(output_list, list) and len(output_list) > 0:
                print(f"Number of records found: {len(output_list)}")
                # Print the first row in detail
                first_row = output_list[0]
                print(f"FIRST ROW FIELDS: {first_row.keys()}")
                for k, v in first_row.items():
                    print(f"  {k}: {v}")
            else:
                print(f"No list data found in response: {res}")
    except Exception as e:
        print(f"FAILED: {e}")

if __name__ == "__main__":
    # Configure logging to see utils.py output
    logging.basicConfig(level=logging.ERROR)
    asyncio.run(test_mcp())
