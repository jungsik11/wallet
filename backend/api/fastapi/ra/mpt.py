import numpy as np
import pandas as pd
from scipy.optimize import minimize
import logging

class ModernPortfolioTheory:
    """
    Modern Portfolio Theory (MPT) Optimizer
    Uses Quadratic Programming (SLSQP) to find optimal asset weights
    subject to specific constraints and bounds.
    """
    
    def __init__(self, expected_returns: pd.Series, cov_matrix: pd.DataFrame):
        """
        Initialize the MPT optimizer.
        """
        if len(expected_returns) != len(cov_matrix):
            raise ValueError("The number of assets in expected_returns and cov_matrix must match.")
            
        self.expected_returns = expected_returns
        self.cov_matrix = cov_matrix
        self.num_assets = len(expected_returns)
        self.assets = expected_returns.index.tolist()
        
    def get_portfolio_variance(self, weights: np.ndarray) -> float:
        """Calculate portfolio variance for given weights."""
        return weights.T @ (self.cov_matrix.values @ weights)
        
    def get_portfolio_return(self, weights: np.ndarray) -> float:
        """Calculate expected portfolio return for given weights."""
        return np.sum(self.expected_returns.values * weights)
        
    def optimize_max_sharpe(self, risk_free_rate: float = 0.0, min_weight: float = 0.0, max_weight: float = 0.23) -> pd.Series:
        """
        Find weights that maximize the Sharpe Ratio using SLSQP optimizer.
        Constraints: Sum of weights = 100%
        Bounds: min_weight <= weight <= max_weight
        """
        def objective(weights):
            p_return = self.get_portfolio_return(weights)
            p_volatility = np.sqrt(self.get_portfolio_variance(weights))
            return -(p_return - risk_free_rate) / (p_volatility + 1e-9)

        constraints = ({'type': 'eq', 'fun': lambda x: np.sum(x) - 1.0})
        bounds = tuple((min_weight, max_weight) for _ in range(self.num_assets))
        init_guess = np.array([1.0 / self.num_assets] * self.num_assets)

        result = minimize(objective, init_guess, method='SLSQP', bounds=bounds, constraints=constraints)
        
        if not result.success:
            logging.error(f"Max Sharpe Optimization failed: {result.message}")
            
        weights_series = pd.Series(result.x, index=self.assets)
        return weights_series
        
    def optimize_min_volatility(self, min_weight: float = 0.0, max_weight: float = 0.23) -> pd.Series:
        """
        Find weights that minimize portfolio volatility using SLSQP optimizer.
        Constraints: Sum of weights = 100%
        Bounds: min_weight <= weight <= max_weight
        """
        def objective(weights):
            return np.sqrt(self.get_portfolio_variance(weights))

        constraints = ({'type': 'eq', 'fun': lambda x: np.sum(x) - 1.0})
        bounds = tuple((min_weight, max_weight) for _ in range(self.num_assets))
        init_guess = np.array([1.0 / self.num_assets] * self.num_assets)

        result = minimize(objective, init_guess, method='SLSQP', bounds=bounds, constraints=constraints)
        
        if not result.success:
            logging.error(f"Min Volatility Optimization failed: {result.message}")

        weights_series = pd.Series(result.x, index=self.assets)
        return weights_series
