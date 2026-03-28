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
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '연도별 총 실현 손익',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView( // For horizontal scrolling if table is too wide
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                  dataTextStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                  columns: const [
                    DataColumn(label: Text('연도')),
                    DataColumn(label: Text('총 실현 손익'), numeric: true),
                  ],
                  rows: sortedYears.map((year) {
                    final totalProfit = yearlyTotalProfit[year] ?? 0.0;
                    final totalProfitColor = totalProfit > 0 ? Colors.greenAccent[400] : (totalProfit < 0 ? Colors.redAccent[400] : Colors.grey);
                    return DataRow(
                      cells: [
                        DataCell(Text(year)),
                        DataCell(Text(
                          _formatCurrency(totalProfit),
                          style: TextStyle(color: totalProfitColor, fontWeight: FontWeight.bold),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
