import 'package:flutter/material.dart';
import 'profit_response.dart';

class YearlyProfitScreen extends StatelessWidget {
  final ProfitResponse profitResponse;

  const YearlyProfitScreen({Key? key, required this.profitResponse}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Sort the years in descending order
    final sortedYears = profitResponse.yearlyTotalProfit.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('연도별 실현 손익'),
      ),
      body: ListView.builder(
        itemCount: sortedYears.length,
        itemBuilder: (context, index) {
          final year = sortedYears[index];
          final totalProfit = profitResponse.yearlyTotalProfit[year] ?? 0.0;

          // Find stocks that had profit in that year
          final stocksForYear = profitResponse.stocks
              .where((stockMap) => stockMap.values.first.yearlyProfit.containsKey(year))
              .toList();

          return Card(
            margin: const EdgeInsets.all(8.0),
            child: ExpansionTile(
              title: Text(
                '$year 총 실현 손익: ${totalProfit.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              children: stocksForYear.map((stockMap) {
                final ticker = stockMap.keys.first;
                final stockHolding = stockMap.values.first;
                final profit = stockHolding.yearlyProfit[year] ?? 0.0;
                return ListTile(
                  title: Text(ticker),
                  trailing: Text(
                    profit.toStringAsFixed(2),
                    style: TextStyle(
                      color: profit >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
