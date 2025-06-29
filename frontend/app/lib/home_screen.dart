import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class PieChartData {
  PieChartData(this.asset, this.value, this.percentage);
  final String asset;
  final double value;
  final double percentage;
}

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> summaryData;

  const HomeScreen({Key? key, required this.summaryData}) : super(key: key);

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
            ),
          ],
        ),
      ),
    );
  }
}
