import asyncio
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import os
import sys

# Mocking parts of app.py to test the core logic
# Add current dir to sys.path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from ra.mpt import ModernPortfolioTheory

# Mock data
mock_tickers = ['005930', 'AAPL', 'MSFT']
mock_names = {'005930': '삼성전자'}

def get_display_name(ticker, mapping):
    return mapping.get(ticker, ticker)

async def test_optimization_logic():
    print("Testing Optimization Logic...")
    
    # 1. Mock Returns and Covariance
    np.random.seed(42)
    days = 252
    returns = pd.DataFrame(np.random.normal(0.001, 0.02, (days, len(mock_tickers))), columns=mock_tickers)
    
    expected_returns = returns.mean() * 252
    cov_matrix = returns.cov() * 252
    rf_rate = 0.035
    
    # 2. Test Pass 1 (Discovery)
    mpt = ModernPortfolioTheory(expected_returns, cov_matrix)
    weights_p1 = mpt.optimize_max_sharpe(risk_free_rate=rf_rate, min_weight=0.0, max_weight=0.23)
    
    print("\nPass 1 Weights (0-23%):")
    for t, w in weights_p1.items():
        print(f"{t}: {w:.4f}")
        
    # 3. Test Pass 2 (Strict 1% floor)
    selected = [t for t, w in weights_p1.items() if w >= 0.01]
    print(f"\nSelected Assets (>= 1%): {selected}")
    
    sub_returns = expected_returns[selected]
    sub_cov = cov_matrix.loc[selected, selected]
    mpt_sub = ModernPortfolioTheory(sub_returns, sub_cov)
    
    weights_p2 = mpt_sub.optimize_max_sharpe(risk_free_rate=rf_rate, min_weight=0.01, max_weight=0.23)
    
    print("\nPass 2 Weights (1-23%):")
    for t, w in weights_p2.items():
        name = get_display_name(t, mock_names)
        print(f"{name} ({t}): {w:.4f}")

    # 4. Verify Constraints
    for t, w in weights_p2.items():
        assert w >= 0.0099, f"Weight for {t} is too low: {w}"
        assert w <= 0.2301, f"Weight for {t} is too high: {w}"
    
    total_w = sum(weights_p2.values())
    assert abs(total_w - 1.0) < 0.001, f"Total weight is not 1.0: {total_w}"
    
    print("\nVerification Successful!")

if __name__ == "__main__":
    asyncio.run(test_optimization_logic())
