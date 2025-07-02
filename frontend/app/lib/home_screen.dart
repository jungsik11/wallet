import 'package:flutter/material.dart';
<<<<<<< Updated upstream

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class PieChartData {
  PieChartData(this.asset, this.value, this.percentage);
  final String asset;
  final double value;
  final double percentage;
}
=======
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
>>>>>>> Stashed changes

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> summaryData;

  const HomeScreen({Key? key, required this.summaryData}) : super(key: key);

<<<<<<< Updated upstream
  String _formatKrw(double value, {bool compact = false}) {
    if (compact) {
      return NumberFormat.compactCurrency(locale: 'ko_KR', symbol: '₩').format(value);
    }
    return NumberFormat.currency(locale: 'ko_KR', symbol: '₩').format(value);
  }

  String _formatUsd(double value) {
    return NumberFormat.currency(locale: 'en_US', symbol: '\$').format(value);
  }

  @override
  Widget build(BuildContext context) {
    if (summaryData.isEmpty) {
      return const Center(child: Text('포트폴리오 데이터가 없습니다.'));
    }

    final totalAssets = (summaryData['total_assets_krw'] as num).toDouble();
    final List<PieChartData> pieData = (summaryData['pie_chart_data'] as List).map((data) {
      final value = (data['value_krw'] as num).toDouble();
      final percentage = totalAssets > 0 ? (value / totalAssets) * 100 : 0.0;
      return PieChartData(data['asset'], value, percentage);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryCard(context),
          const SizedBox(height: 24),
          Text('자산 구성', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _buildPieChart(pieData),
          const SizedBox(height: 24),
          _buildDataTable(pieData),
        ],
      ),
    );
  }

  Widget _buildPieChart(List<PieChartData> pieData) {
    return SizedBox(
      height: 400,
      child: SfCircularChart(
        series: <CircularSeries>[
          PieSeries<PieChartData, String>(
            dataSource: pieData,
            xValueMapper: (PieChartData data, _) => data.asset,
            yValueMapper: (PieChartData data, _) => data.value,
            dataLabelMapper: (PieChartData data, _) => '${data.percentage.toStringAsFixed(1)}%', // Percentage inside
            dataLabelSettings: DataLabelSettings(
                isVisible: true,
                textStyle: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                // Use the builder for custom outside labels
                builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                  final chartData = data as PieChartData;
                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${chartData.asset}\n${_formatKrw(chartData.value, compact: true)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  );
                }
            ),
            enableTooltip: true,
          )
        ],
      ),
    );
  }

  Widget _buildDataTable(List<PieChartData> pieData) {
    return DataTable(
      columns: const [
        DataColumn(label: Text('자산')),
        DataColumn(label: Text('평가 금액'), numeric: true),
        DataColumn(label: Text('비중'), numeric: true),
      ],
      rows: pieData.map((data) {
        return DataRow(
          cells: [
            DataCell(Text(data.asset)),
            DataCell(Text(_formatKrw(data.value))),
            DataCell(Text('${data.percentage.toStringAsFixed(2)}%')),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final totalAssets = (summaryData['total_assets_krw'] as num).toDouble();
    final krwDeposit = (summaryData['krw_deposit'] as num).toDouble();
    final usdDeposit = (summaryData['usd_deposit'] as num).toDouble();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('총 자산', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_formatKrw(totalAssets), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 32, thickness: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text('원화 예수금', style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Text(_formatKrw(krwDeposit), style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                Column(
                  children: [
                    Text('달러 예수금', style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Text(_formatUsd(usdDeposit), style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ],
=======
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
>>>>>>> Stashed changes
            ),
          ],
        ),
      ),
    );
  }
}
<<<<<<< Updated upstream
=======

class _PieData {
  _PieData(this.x, this.y);
  final String x;
  final double y;
}
>>>>>>> Stashed changes
