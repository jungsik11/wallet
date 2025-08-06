"""
Provides functions for trend analysis on financial time-series data.
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Any

def calculate_trend(ohlcv_data: List[Dict[str, Any]], period: int = 30, slope_threshold: float = 0.05) -> Dict[str, Any]:
    """
    Analyzes the provided OHLCV data to determine the trend using linear regression.

    Args:
        ohlcv_data: A list of dictionaries, each representing an OHLCV bar.
                    Must contain at least 'date' and 'close' keys.
        period: The number of recent data points to use for the trend calculation.
        slope_threshold: The minimum normalized slope to be considered a significant
                         trend. Below this, it's considered sideways.

    Returns:
        A dictionary containing the determined trend ('Uptrend', 'Downtrend',
        'Sideways'), the normalized slope, and the start/end points of the trendline.
    """
    # Use all available data if less than the specified period
    recent_data = ohlcv_data[-period:] if len(ohlcv_data) >= period else ohlcv_data
    
    df = pd.DataFrame(recent_data)
    df['close'] = pd.to_numeric(df['close'])
    df['date'] = pd.to_datetime(df['date'], format='mixed')
    
    # Create a numerical index for regression
    x = np.arange(len(df))
    y = df['close'].values

    # Fit a linear regression line
    try:
        slope, intercept = np.polyfit(x, y, 1)
    except np.linalg.LinAlgError:
        return {'trend': 'Analysis Failed', 'slope': 0, 'trendline': {}}

    # Normalize the slope to make it comparable across different price ranges
    normalized_slope = slope / y.mean()

    # Determine the trend
    if normalized_slope > slope_threshold:
        trend = 'Uptrend'
    elif normalized_slope < -slope_threshold:
        trend = 'Downtrend'
    else:
        trend = 'Sideways'

    # Calculate trendline start and end points for plotting
    trendline_start = slope * x[0] + intercept
    trendline_end = slope * x[-1] + intercept

    return {
        'trend': trend, 
        'normalized_slope': round(normalized_slope, 4),
        'trendline': {
            'start_date': df['date'].iloc[0].isoformat(),
            'start_value': round(trendline_start, 2),
            'end_date': df['date'].iloc[-1].isoformat(),
            'end_value': round(trendline_end, 2)
        }
    }

# --- Example Usage (for testing) ---
if __name__ == '__main__':
    # Sample data
    sample_data = [{'date': f'2024-01-{i:02d}', 'close': 100 + i * 0.7} for i in range(1, 41)]
    
    # Calculate trend
    trend_result = calculate_trend(sample_data, period=30, slope_threshold=0.001)
    
    print("--- Trend Analysis Result ---")
    print(f"Determined Trend: {trend_result.get('trend')}")
    print(f"Normalized Slope: {trend_result.get('normalized_slope')}")
    print(f"Trendline: {trend_result.get('trendline')}")
