
"""
Aggregates and summarizes trading activities and performance.
"""

from typing import Dict, List, Any
import pandas as pd

class TradeAggregator:
    """
    Manages a log of trades and calculates performance metrics.
    """
    def __init__(self):
        self.trades = [] # List of all executed trades
        self.positions = {} # Current open positions
        self.closed_trades = [] # List of closed (buy-sell) trade pairs

    def record_buy(self, signal: Dict[str, Any]):
        """
        Records a buy signal and opens a new position.
        """
        trade_id = f"{signal['ticker']}-{len(self.trades)}"
        self.trades.append({
            'trade_id': trade_id,
            'ticker': signal['ticker'],
            'type': 'BUY',
            'price': signal['price'],
            'time': signal['signal_time'],
            'status': 'OPEN'
        })
        self.positions[signal['ticker']] = {
            'trade_id': trade_id,
            'buy_price': signal['price'],
            'buy_time': signal['signal_time']
        }
        print(f"[TradeAggregator] Recorded BUY for {signal['ticker']} at {signal['price']}")

    def record_sell(self, signal: Dict[str, Any]):
        """
        Records a sell signal and closes an existing position.
        Calculates profit/loss for the closed trade.
        """
        ticker = signal['ticker']
        if ticker in self.positions:
            buy_info = self.positions.pop(ticker)
            sell_price = signal['price']
            buy_price = buy_info['buy_price']
            
            profit_loss = sell_price - buy_price # Simplified P/L per share

            self.trades.append({
                'trade_id': buy_info['trade_id'],
                'ticker': ticker,
                'type': 'SELL',
                'price': sell_price,
                'time': signal['signal_time'],
                'status': 'CLOSED'
            })
            self.closed_trades.append({
                'ticker': ticker,
                'buy_price': buy_price,
                'sell_price': sell_price,
                'profit_loss': profit_loss,
                'duration': (pd.to_datetime(signal['signal_time']) - pd.to_datetime(buy_info['buy_time'])).total_seconds() / 60 # in minutes
            })
            print(f"[TradeAggregator] Recorded SELL for {ticker} at {sell_price}. P/L: {profit_loss:.2f}")
        else:
            print(f"[TradeAggregator] Warning: Sell signal for {ticker} but no open position found.")
            # Record as a standalone sell if no matching buy (e.g., manual close)
            self.trades.append({
                'trade_id': f"{ticker}-SELL-{len(self.trades)}",
                'ticker': ticker,
                'type': 'SELL',
                'price': signal['price'],
                'time': signal['signal_time'],
                'status': 'STANDALONE_SELL'
            })

    def get_summary(self) -> Dict[str, Any]:
        """
        Returns a summary of all recorded trades and performance metrics.
        """
        total_profit_loss = sum(t['profit_loss'] for t in self.closed_trades)
        winning_trades = sum(1 for t in self.closed_trades if t['profit_loss'] > 0)
        losing_trades = sum(1 for t in self.closed_trades if t['profit_loss'] <= 0)
        total_closed_trades = len(self.closed_trades)
        win_rate = (winning_trades / total_closed_trades * 100) if total_closed_trades > 0 else 0.0

        return {
            'total_trades_recorded': len(self.trades),
            'open_positions': len(self.positions),
            'closed_trades_count': total_closed_trades,
            'total_profit_loss': round(total_profit_loss, 2),
            'winning_trades': winning_trades,
            'losing_trades': losing_trades,
            'win_rate': round(win_rate, 2),
            'average_profit_per_trade': round(total_profit_loss / total_closed_trades, 2) if total_closed_trades > 0 else 0.0
        }

    def get_trade_log(self) -> List[Dict[str, Any]]:
        """
        Returns the full list of all recorded trades.
        """
        return self.trades

    def get_closed_trades(self) -> List[Dict[str, Any]]:
        """
        Returns the list of all closed trade pairs.
        """
        return self.closed_trades

# --- Example Usage (for testing) ---
if __name__ == '__main__':
    aggregator = TradeAggregator()

    # Simulate some trades
    aggregator.record_buy({'ticker': 'AAPL', 'price': 150.0, 'signal_time': '2024-01-01T09:30:00', 'type': 'BUY'})
    aggregator.record_buy({'ticker': 'MSFT', 'price': 300.0, 'signal_time': '2024-01-01T09:35:00', 'type': 'BUY'})

    aggregator.record_sell({'ticker': 'AAPL', 'price': 155.0, 'signal_time': '2024-01-01T10:00:00', 'type': 'SELL', 'buy_price': 150.0})
    aggregator.record_sell({'ticker': 'GOOG', 'price': 100.0, 'signal_time': '2024-01-01T10:05:00', 'type': 'SELL', 'buy_price': 105.0})

    # Print summary
    print("\n--- Trade Summary ---")
    print(aggregator.get_summary())

    print("\n--- Full Trade Log ---")
    for trade in aggregator.get_trade_log():
        print(trade)

    print("\n--- Closed Trades ---")
    for trade in aggregator.get_closed_trades():
        print(trade)
