import asyncio
import os
import sys
import logging

# Ensure we can import from the current directory
sys.path.append(os.getcwd())

async def test_mcp():
    from utils import call_mcp_tool, MCP_STOCK_SERVER_URL
    print(f"--- Testing MCP Connection to {MCP_STOCK_SERVER_URL} ---")
    
    symbols = ["0001", "KORPT038"]
    tools = ["inquire_index_price", "inquire_index_daily_price", "inquire_daily_indexchartprice"]
    
    for tool in tools:
        print(f"\n===== TESTING TOOL: {tool} =====")
        for symbol in symbols:
            params = {
                "fid_cond_mrkt_div_code": "U",
                "fid_input_iscd": symbol,
                "tr_cont": ""
            }
            if tool == "inquire_index_daily_price":
                params["fid_period_div_code"] = "D"
            if tool == "inquire_daily_indexchartprice":
                params["fid_period_div_code"] = "D"
                # Add some more required params for chart if needed
                params["fid_org_adj_prc"] = "0"
            
            print(f"\n--- Symbol: {symbol} ---")
            try:
                res = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", tool, params)
                print(f"RESULT: {res}")
                
                # Check for any non-zero price
                if isinstance(res, dict):
                    # Check list output (some daily tools return lists in 'output2')
                    if 'output2' in res and isinstance(res['output2'], list) and len(res['output2']) > 0:
                        top = res['output2'][0]
                        print(f"Top Output2 Entry: {top}")
            except Exception as e:
                print(f"Error calling {tool} for {symbol}: {e}")

if __name__ == "__main__":
    # Configure logging to see utils.py output
    logging.basicConfig(level=logging.ERROR)
    asyncio.run(test_mcp())
