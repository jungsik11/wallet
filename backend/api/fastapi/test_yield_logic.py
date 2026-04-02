import asyncio
from unittest.mock import MagicMock, patch
import pandas as pd

# Mocking FinanceDataReader
class MockFDR:
    def DataReader(self, code):
        if self.mock_data and code in self.mock_data:
            return self.mock_data[code]
        return pd.DataFrame()

mock_fdr = MockFDR()

# The function to test (copied from app.py for logic check)
async def test_logic(latest_yield_val):
    def normalize(val):
        if val > 200: return val / 10000.0
        if val > 0.1: return val / 100.0
        return val

    candidate = normalize(latest_yield_val)
    if 0.005 <= candidate <= 0.15:
        return candidate
    return 0.035 # Fallback

async def run_tests():
    print(f"94.1 -> {await test_logic(94.1)}")
    print(f"3.59 -> {await test_logic(3.59)}")
    print(f"359 -> {await test_logic(359)}")
    print(f"0.0359 -> {await test_logic(0.0359)}")
    print(f"0.0 -> {await test_logic(0.0)}")

if __name__ == "__main__":
    asyncio.run(run_tests())
