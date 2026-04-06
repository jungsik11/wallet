import asyncio
import logging
import sys
import os

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from utils import call_mcp_tool, MCP_STOCK_SERVER_URL

logging.basicConfig(level=logging.INFO)

async def test_rankings():
    print("--- Testing US Market Cap Ranking ---")
    params_us = {
        "auth": "",
        "excd": "NAS",
        "co_yn_pricecur": "0",
        "co_yn_rate": "0",
        "co_yn_valx": "1",
        "co_st_valx": "100000000", # 100 billion USD
        "co_en_valx": "99999999999",
        "keyb": ""
    }
    try:
        data_us = await call_mcp_tool(MCP_STOCK_SERVER_URL, "overseas_stock", "inquire_search", params_us)
        if data_us and data_us.get("output2"):
            print(f"US Success! Found {len(data_us['output2'])} stocks.")
            top_stock = data_us['output2'][0]
            print(f"Top Stock: {top_stock.get('symb')} - {top_stock.get('name')}")
        else:
            print(f"US Empty or Failed. Response: {data_us}")
    except Exception as e:
        print(f"US Error: {e}")

    print("\n--- Testing KR Market Cap Ranking ---")
    params_kr = {
        "fid_cond_scr_no": "20173",
        "fid_cond_mrkt_div_code": "J",
        "fid_input_iscd": "0000",
        "fid_div_cls_code": "0",
        "fid_rank_sort_cls_code": "0",
        "fid_etc_cls_code": "0"
    }
    try:
        data_kr = await call_mcp_tool(MCP_STOCK_SERVER_URL, "domestic_stock", "inquire_ranking", params_kr)
        if data_kr and data_kr.get("output"):
            print(f"KR Success! Found {len(data_kr['output'])} stocks.")
            top_stock_kr = data_kr['output'][0]
            print(f"Top Stock: {top_stock_kr.get('hts_kor_isnm')} ({top_stock_kr.get('mksc_shrn_iscd')})")
        else:
            print(f"KR Empty or Failed. Response: {data_kr}")
    except Exception as e:
        print(f"KR Error: {e}")

if __name__ == "__main__":
    asyncio.run(test_rankings())
