
import asyncio
import json
from gemini_tools import overseas_stock

async def get_us_market_cap_ranking():
    all_stocks = []
    for excd in ["NYS", "NAS", "AMS"]:
        params = {
            "auth": "",
            "excd": excd,
            "co_yn_pricecur": "0", "co_st_pricecur": "", "co_en_pricecur": "",
            "co_yn_rate": "0", "co_st_rate": "", "co_en_rate": "",
            "co_yn_valx": "1",
            "co_st_valx": "1000000000",  # 1 Trillion USD in thousands
            "co_en_valx": "9999999999999",
            "co_yn_shar": "0", "co_st_shar": "", "co_en_shar": "",
            "co_yn_volume": "0", "co_st_volume": "", "co_en_volume": "",
            "co_yn_amt": "0", "co_st_amt": "", "co_en_amt": "",
            "co_yn_eps": "0", "co_st_eps": "", "co_en_eps": "",
            "co_yn_per": "0", "co_st_per": "", "co_en_per": "",
            "keyb": ""
        }
        try:
            data = await overseas_stock(api_type="inquire_search", params=params)
            if data and data.get("output2"):
                all_stocks.extend(data["output2"])
        except Exception as e:
            print(f"Error fetching data for {excd}: {e}")

    unique_stocks = {stock['symb']: stock for stock in all_stocks}.values()
    
    # Sort by market_cap in descending order
    sorted_stocks = sorted(unique_stocks, key=lambda x: float(x.get('valx', 0)), reverse=True)
    
    print("Ticker,Name,MarketCap_Trillion")
    for stock in sorted_stocks:
        market_cap_trillion = float(stock.get('valx', 0)) / 1000000000
        if market_cap_trillion >= 1:
            print(f"{stock.get('symb')},{stock.get('name')},{market_cap_trillion:.2f}")

if __name__ == "__main__":
    asyncio.run(get_us_market_cap_ranking())
