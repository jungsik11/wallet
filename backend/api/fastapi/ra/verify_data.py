import pandas as pd
import yfinance as yf
import os

def verify_universe():
    print("--- Verifying KR ETF Universe ---")
    csv_path = 'backend/ra/kr_etfs_universe.csv'
    if not os.path.exists(csv_path):
        print(f"Error: {csv_path} not found.")
        return

    df = pd.read_csv(csv_path)
    tickers = [f"{str(symbol).zfill(6)}.KS" for symbol in df['Symbol']]
    
    print(f"Total tickers to verify: {len(tickers)}")
    
    # Try to fetch last 5 days of data for all
    try:
        data = yf.download(tickers, period="5d", threads=False)
        if data.empty:
            print("Error: No data fetched at all.")
            return

        # Check for any tickers that returned all NaNs
        close_data = data['Close']
        failed_tickers = []
        for ticker in tickers:
            if ticker not in close_data.columns or close_data[ticker].isnull().all():
                failed_tickers.append(ticker)
        
        if failed_tickers:
            print(f"Warning: Failed to fetch data for {len(failed_tickers)} tickers:")
            for ft in failed_tickers:
                name = df[df['Symbol'].astype(str).str.zfill(6) == ft.split('.')[0]]['Name'].values[0]
                print(f"  - {ft} ({name})")
        else:
            print("Success! All tickers fetched correctly.")
            
    except Exception as e:
        print(f"Exception during verification: {e}")

if __name__ == "__main__":
    verify_universe()
