import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> summaryData;

  const HomeScreen({Key? key, required this.summaryData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final pieData = summaryData['pie_data'] as Map<String, dynamic>?;
    final holdings = summaryData['holdings'] as List<dynamic>?;

    if (pieData == null || holdings == null) {
      return const Center(child: Text('포트폴리오 데이터가 없습니다.'));
    }

    final krwValuation = (pieData['krw_valuation'] as num?)?.toDouble() ?? 0.0;
    final usdValuationInKrw = (pieData['usd_valuation_in_krw'] as num?)?.toDouble() ?? 0.0;
    final totalValuation = krwValuation + usdValuationInKrw;

    final List<_PieData> chartData = [
      if (krwValuation > 0) _PieData('원화 자산', krwValuation),
      if (usdValuationInKrw > 0) _PieData('달러 자산', usdValuationInKrw),
    ];

    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final usdCurrencyFormat = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final percentFormat = NumberFormat.decimalPercentPattern(decimalDigits: 2);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('자산 구성', style: Theme.of(context).textTheme.titleLarge),
            if (chartData.isNotEmpty)
              SizedBox(
                height: 300,
                child: SfCircularChart(
                  title: ChartTitle(text: '총 평가금액: ${currencyFormat.format(totalValuation)}'),
                  legend: const Legend(isVisible: true, overflowMode: LegendItemOverflowMode.wrap),
                  series: <CircularSeries<_PieData, String>>[
                    PieSeries<_PieData, String>(
                      dataSource: chartData,
                      xValueMapper: (_PieData data, _) => data.x,
                      yValueMapper: (_PieData data, _) => data.y,
                      dataLabelMapper: (data, _) => '${(data.y / totalValuation * 100).toStringAsFixed(1)}%',
                      dataLabelSettings: const DataLabelSettings(isVisible: true),
                    )
                  ],
                ),
              )
            else
              const SizedBox(height: 300, child: Center(child: Text("보유 자산이 없습니다."))),
            const SizedBox(height: 20),
            Text('보유 종목 현황', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: DataTable(
                columnSpacing: 16,
                horizontalMargin: 0,
                columns: const [
                  DataColumn(label: Text('종목명')),
                  DataColumn(label: Text('평가금액'), numeric: true),
                  DataColumn(label: Text('현재가'), numeric: true),
                  DataColumn(label: Text('수익률'), numeric: true),
                  DataColumn(label: Text('평균단가'), numeric: true),
                ],
                rows: holdings.map((holding) {
                  final isUsd = holding['currency'] == 'USD';
                  final valuation = (holding['valuation'] as num).toDouble();
                  final currentPrice = (holding['current_price'] as num).toDouble();
                  final avgPrice = (holding['average_price'] as num).toDouble();
                  final profitRatio = (holding['profit_loss_ratio'] as num).toDouble();

                  return DataRow(
                    cells: [
                      DataCell(SizedBox(width: 100, child: Text(holding['name'], overflow: TextOverflow.ellipsis))),
                      DataCell(Text(isUsd ? usdCurrencyFormat.format(valuation) : currencyFormat.format(valuation))),
                      DataCell(Text(isUsd ? usdCurrencyFormat.format(currentPrice) : currencyFormat.format(currentPrice))),
                      DataCell(
                        Text(
                          percentFormat.format(profitRatio / 100),
                          style: TextStyle(color: profitRatio >= 0 ? Colors.green : Colors.red),
                        ),
                      ),
                      DataCell(Text(isUsd ? usdCurrencyFormat.format(avgPrice) : currencyFormat.format(avgPrice))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PieData {
  _PieData(this.x, this.y);
  final String x;
  final double y;
}
