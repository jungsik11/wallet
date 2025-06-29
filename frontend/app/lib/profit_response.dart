class ProfitResponse {
  final Map<String, double> yearlyTotalProfit;
  final List<Map<String, StockHolding>> stocks;

  ProfitResponse({required this.yearlyTotalProfit, required this.stocks});

  factory ProfitResponse.fromJson(Map<String, dynamic> json) {
    var stocksList = (json['stocks'] as List)
        .map((item) {
          final entry = (item as Map<String, dynamic>).entries.first;
          return {
            entry.key: StockHolding.fromJson(entry.value as Map<String, dynamic>)
          };
        })
        .toList();

    return ProfitResponse(
      yearlyTotalProfit: Map<String, double>.from(json['yearly_total_profit'].map((key, value) => MapEntry(key, (value as num).toDouble()))),
      stocks: stocksList,
    );
  }
}

class StockHolding {
  final Map<String, double> yearlyProfit;
  final Map<String, dynamic> holdings;

  StockHolding({required this.yearlyProfit, required this.holdings});

  factory StockHolding.fromJson(Map<String, dynamic> json) {
    return StockHolding(
      yearlyProfit: Map<String, double>.from(json['yearly_profit'].map((key, value) => MapEntry(key, (value as num).toDouble()))),
      holdings: Map<String, dynamic>.from(json['holdings']),
    );
  }
}
