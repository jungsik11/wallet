import numpy as np
import pandas as pd

class ModernPortfolioTheory:
    """
    Modern Portfolio Theory (MPT) Optimizer
    Finds optimal asset weights using numerical simulation (Monte Carlo).
    """
    
    def __init__(self, expected_returns: pd.Series, cov_matrix: pd.DataFrame, num_portfolios: int = 100000):
        """
        Initialize the MPT optimizer.
        """
        if len(expected_returns) != len(cov_matrix):
            raise ValueError("The number of assets in expected_returns and cov_matrix must match.")
            
        self.expected_returns = expected_returns
        self.cov_matrix = cov_matrix
        self.num_assets = len(expected_returns)
        self.assets = expected_returns.index.tolist()
        self.num_portfolios = num_portfolios
        
    def get_portfolio_variance(self, weights: np.ndarray) -> float:
        """Calculate portfolio variance for given weights."""
        return weights.T @ (self.cov_matrix.values @ weights)
        
    def get_portfolio_return(self, weights: np.ndarray) -> float:
        """Calculate expected portfolio return for given weights."""
        return np.sum(self.expected_returns.values * weights)
        
    def _generate_random_portfolios(self):
        """Vectorized generation of random portfolio weights, returns, and volatilities."""
        # Generate random weights and row-normalize to sum to 1
        weights = np.random.random((self.num_portfolios, self.num_assets))
        weights = weights / np.sum(weights, axis=1)[:, np.newaxis]
        
        # Calculate returns
        returns = np.dot(weights, self.expected_returns.values)
        
        # Calculate volatilities efficiently using numpy batch dot product
        # weights: (M, N), cov: (N, N) => weights @ cov => (M, N)
        # then element-wise multiply with weights and sum over N (axis=1)
        cov_val = self.cov_matrix.values
        var = np.sum(weights * np.dot(weights, cov_val), axis=1)
        vols = np.sqrt(var)
        
        return weights, returns, vols
        
    def optimize_max_sharpe(self, risk_free_rate: float = 0.0) -> pd.Series:
        """
        Find the optimal weights that maximize the Sharpe Ratio.
        """
        weights, returns, vols = self._generate_random_portfolios()
        sharpe_ratios = (returns - risk_free_rate) / (vols + 1e-9)
        max_idx = np.argmax(sharpe_ratios)
        
        best_weights = weights[max_idx]
        weights_series = pd.Series(best_weights, index=self.assets)
        return weights_series
        
    def optimize_min_volatility(self) -> pd.Series:
        """
        Find the optimal weights that minimize portfolio volatility.
        """
        weights, returns, vols = self._generate_random_portfolios()
        min_idx = np.argmin(vols)
        
        best_weights = weights[min_idx]
        weights_series = pd.Series(best_weights, index=self.assets)
        return weights_series
