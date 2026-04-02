import FinanceDataReader as fdr
import pandas as pd

codes = ['KR3YT=RR', 'KRDR1Y3', 'KTB3Y', 'KR10YT=RR']
results = {}

for code in codes:
    try:
        df = fdr.DataReader(code)
        if df is not None and not df.empty:
            latest = df.iloc[-1]['Close']
            results[code] = latest
        else:
            results[code] = "Empty"
    except Exception as e:
        results[code] = f"Error: {e}"

print(results)
with open('bond_check.txt', 'w') as f:
    f.write(str(results))
