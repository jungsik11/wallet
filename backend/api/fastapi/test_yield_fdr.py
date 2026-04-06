import FinanceDataReader as fdr
import datetime

def test_fdr():
    print("--- Testing FDR for KTB 3Y Yield ---")
    sources = [
        ('KR3YT=RR', 'investing'),
        ('KR10YT=RR', 'investing'),
        ('KORPT038', None),
        ('FRED:KORINT3YRT156N', None)
    ]
    
    for symbol, source in sources:
        print(f"\nTrying {symbol} (source: {source})...")
        try:
            if source:
                df = fdr.DataReader(symbol, data_source=source)
            else:
                df = fdr.DataReader(symbol)
            
            if df is not None and not df.empty:
                print(f"SUCCESS: {symbol}")
                print(df.tail(1))
            else:
                print(f"FAILED: Empty DF for {symbol}")
        except Exception as e:
            print(f"ERROR for {symbol}: {e}")

if __name__ == "__main__":
    test_fdr()
