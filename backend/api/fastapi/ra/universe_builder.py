print("Importing os...")
import os
print("Importing pandas...")
import pandas as pd
print("Importing yfinance...")
import yfinance as yf
print("Importing FinanceDataReader...")
import FinanceDataReader as fdr
print("Importing finvizfinance...")
from finvizfinance.screener.overview import Overview
print("Finished imports.")

def build_us_stocks_universe():
    print("Fetching Mega Cap US Stocks from Finviz...")
    foverview = Overview()
    
    # Filter for Mega Cap ($200bln and over) to reduce the yfinance API call load
    foverview.set_filter(filters_dict={'Market Cap.': 'Mega ($200bln and over)'})
    try:
        df_mega = foverview.screener_view()
        tickers = df_mega['Ticker'].tolist()
    except Exception as e:
        print("Finviz fetch failed, using known mega cap list as fallback", e)
        # Fallback if finviz changes their HTML layout
        tickers = ['AAPL', 'MSFT', 'NVDA', 'GOOGL', 'AMZN', 'META', 'TSLA', 'BRK-B', 'LLY', 'AVGO', 'JPM', 'V', 'WMT']

    print(f"Checking precise market caps via yfinance for {len(tickers)} candidates...")
    
    trillion_club = []
    
    for ticker in tickers:
        try:
            stock = yf.Ticker(ticker)
            info = stock.info
            # 'marketCap' could be missing occasionally
            mcap = info.get('marketCap', 0)
            
            # $1 Trillion = 1,000,000,000,000
            if mcap >= 1_000_000_000_000:
                trillion_club.append({
                    'Ticker': ticker,
                    'Name': info.get('shortName', ticker),
                    'MarketCap_Trillion': round(mcap / 1e12, 2)
                })
                print(f"Added: {ticker} (Market Cap: {round(mcap / 1e12, 2)}T)")
        except Exception as e:
            print(f"Error fetching {ticker}: {e}")
            
    df_result = pd.DataFrame(trillion_club)
    
    if not df_result.empty:
        df_result = df_result.sort_values(by='MarketCap_Trillion', ascending=False).reset_index(drop=True)
        # Ensure 'ra' directory exists inside 'backend'
        os.makedirs('ra', exist_ok=True)
        df_result.to_csv('ra/us_stocks_1T_universe.csv', index=False)
        print("\n[US $1T+ Stocks]")
        print(df_result.to_string())
    else:
        print("No stocks found over $1T.")
    
    return df_result


def build_kr_etfs_universe():
    print("\nFetching Korean ETFs from FinanceDataReader...")
    # 'ETF/KR' fetches all domestic ETFs
    df_all_etfs = fdr.StockListing('ETF/KR')
    print(f"Fetched {len(df_all_etfs)} Korean ETFs.")
    
    # Save full dump for reference
    df_all_etfs.to_csv('ra/kr_etfs_all.csv', index=False)
    print("Saved all KR ETFs to ra/kr_etfs_all.csv")

    # Update curated list if it exists
    curated_path = 'ra/kr_etfs_universe.csv'
    if os.path.exists(curated_path):
        print(f"Updating names in curated list: {curated_path}")
        df_curated = pd.read_csv(curated_path)
        
        # Ensure Symbol is string for matching
        df_curated['Symbol'] = df_curated['Symbol'].astype(str).str.zfill(6)
        df_all_etfs['Symbol'] = df_all_etfs['Symbol'].astype(str).str.zfill(6)
        
        # Merge to get latest names from fdr
        # We keep the AssetClass from the curated list
        df_updated = df_curated.merge(
            df_all_etfs[['Symbol', 'Name']], 
            on='Symbol', 
            how='left', 
            suffixes=('_old', '')
        )
        
        # Use new name if available, otherwise keep old
        df_updated['Name'] = df_updated['Name'].fillna(df_updated['Name_old'])
        df_updated = df_updated[['Symbol', 'Name', 'AssetClass']]
        
        df_updated.to_csv(curated_path, index=False)
        print(f"Updated {len(df_updated)} assets in {curated_path}")
    else:
        # If no curated list, save the sample as a starting point
        print("No curated list found. Creating initial sample.")
        df_all_etfs.head(20).to_csv(curated_path, index=False)
    
    return df_all_etfs

if __name__ == "__main__":
    print("--- Building Asset Universe ---")
    build_us_stocks_universe()
    build_kr_etfs_universe()
    print("\nUniverse building complete!")
