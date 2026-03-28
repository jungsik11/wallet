import os
print("Importing numpy...")
import numpy as np
print("Importing pandas...")
import pandas as pd
print("Importing yfinance...")
import yfinance as yf
print("Importing ra.mpt...")
from ra.mpt import ModernPortfolioTheory
print("Imports done.")

def fetch_data(tickers, start_date, end_date):
    print(f"Fetching data from yfinance for {len(tickers)} assets...")
    # Disable threads to avoid macOS threading hangs
    data_raw = yf.download(tickers, start=start_date, end=end_date, threads=False)
    data = data_raw['Close'] if 'Close' in data_raw else data_raw.xs('Close', level=1, axis=1) if isinstance(data_raw.columns, pd.MultiIndex) else data_raw
    
    # Calculate daily returns and drop NaNs
    daily_returns = data.pct_change().dropna()
    
    # Annualize expected returns (assuming 252 trading days in a year)
    expected_returns = daily_returns.mean() * 252
    
    # Annualize covariance matrix
    cov_matrix = daily_returns.cov() * 252
    
    return expected_returns, cov_matrix

def test_mpt_optimization():
    print("Preparing real market data for diverse asset classes...")
    
    # Representative ETFs: 
    # SPY (US Stock)
    # 069500.KS (KODEX 200 KR Stock)
    # 114260.KS (KODEX 3Y Bond (국고채))
    # GLD (Gold Commodity)
    # 261240.KS (KODEX US Dollar Futures) -> Or we use USDKRW=X though it's not an ETF, let's use 261240.KS
    
    tickers = ['SPY', '069500.KS', '114260.KS', 'GLD', '261240.KS']
    
    asset_names = {
        'SPY': 'US S&P500 (SPY)',
        '069500.KS': 'KODEX 200 (KR Stock)',
        '114260.KS': 'KODEX 3Y Bond (KR Bond)',
        'GLD': 'Gold (Commodity)',
        '261240.KS': 'KODEX US Dollar Futures'
    }
    
    # Fetch past 2 years of data
    start_date = "2024-01-01"
    end_date = "2026-03-27"
    
    expected_returns, cov_matrix = fetch_data(tickers, start_date, end_date)
    
    # Rename columns/index to readable names
    expected_returns.rename(index=asset_names, inplace=True)
    cov_matrix.rename(index=asset_names, columns=asset_names, inplace=True)
    
    print("\n--- Expected Returns (Annualized) ---")
    print(expected_returns)
    print("\n--- Covariance Matrix (Annualized) ---")
    print(cov_matrix)
    
    mpt = ModernPortfolioTheory(expected_returns, cov_matrix)
    
    print("\n--- Maximize Sharpe Ratio ---")
    try:
        sharpe_weights = mpt.optimize_max_sharpe(risk_free_rate=0.035) # Using 3.5% as risk-free rate
        print("Weights:\n", sharpe_weights.apply(lambda x: round(x, 4)))
        print("Sum of weights:", round(sharpe_weights.sum(), 4))
        print("Portfolio Return (Annualized):", round(mpt.get_portfolio_return(sharpe_weights), 4))
        print("Portfolio Volatility (Annualized):", round(np.sqrt(mpt.get_portfolio_variance(sharpe_weights)), 4))
    except Exception as e:
        print("Error during Max Sharpe:", e)
        
    print("\n--- Minimize Volatility ---")
    try:
        min_vol_weights = mpt.optimize_min_volatility()
        print("Weights:\n", min_vol_weights.apply(lambda x: round(x, 4)))
        print("Sum of weights:", round(min_vol_weights.sum(), 4))
        print("Portfolio Return (Annualized):", round(mpt.get_portfolio_return(min_vol_weights), 4))
        print("Portfolio Volatility (Annualized):", round(np.sqrt(mpt.get_portfolio_variance(min_vol_weights)), 4))
    except Exception as e:
        print("Error during Min Vol:", e)

if __name__ == "__main__":
    test_mpt_optimization()
