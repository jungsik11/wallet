import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'profit_response.dart';

class YearlyProfitScreen extends StatelessWidget {
  final ProfitResponse profitResponse;
  final String country;

  const YearlyProfitScreen({Key? key, required this.profitResponse, required this.country}) : super(key: key);

  String _formatCurrency(double value) {
    if (country == 'US') {
      final format = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
      return format.format(value);
    } else if (country == 'KR') {
      final format = NumberFormat('#,##0.00');
      return '${format.format(value / 10000)}만원';
    } else {
      final format = NumberFormat('#,##0.00');
      return format.format(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final yearlyTotalProfit = profitResponse.yearlyTotalProfit;
    final sortedYears = yearlyTotalProfit.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('연도별 실현 손익'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: ListView.builder(
        itemCount: sortedYears.length,
        itemBuilder: (context, index) {
          final year = sortedYears[index];
          final totalProfit = yearlyTotalProfit[year] ?? 0.0;
          final totalProfitColor = totalProfit > 0 ? Colors.greenAccent[400] : (totalProfit < 0 ? Colors.redAccent[400] : Colors.grey);

          // Find all stocks that had trades in this year
          final stocksForYear = profitResponse.stocks.where((stockMap) {
            return stockMap.values.first.yearlyProfit.containsKey(year);
          }).toList();

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            elevation: 4,
            child: ExpansionTile(
              title: Text(
                '$year 총 실현 손익',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _formatCurrency(totalProfit),
                style: TextStyle(color: totalProfitColor, fontWeight: FontWeight.bold),
              ),
              children: stocksForYear.map((stockMap) {
                final ticker = stockMap.keys.first;
                final stockHolding = stockMap.values.first;
                final profit = stockHolding.yearlyProfit[year] ?? 0.0;
                final profitColor = profit > 0 ? Colors.greenAccent[400] : (profit < 0 ? Colors.redAccent[400] : Colors.grey);

                return ListTile(
                  title: Text(ticker, style: theme.textTheme.bodyLarge),
                  trailing: Text(
                    _formatCurrency(profit),
                    style: TextStyle(
                      color: profitColor,
                      fontWeight: FontWeight.bold,
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
