import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> usProfitData;
  final List<dynamic> usBalanceData;
  final Map<String, dynamic> krProfitData;
  final List<dynamic> krBalanceData;
  final Map<String, dynamic> pensionBalanceData;
  final double? usExchangeRate; // Add this line

  const HomeScreen({
    Key? key,
    required this.usProfitData,
    required this.usBalanceData,
    required this.krProfitData,
    required this.krBalanceData,
    required this.pensionBalanceData,
    this.usExchangeRate, // Add this line
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Extract current estimated profit/loss for US and KR stocks
    // Assuming 'total_profit' key holds the current profit/loss
    final double usCurrentProfitUsd = usBalanceData.fold<double>(0.0, (sum, item) => sum + ((item['profit_loss_usd'] as num?)?.toDouble() ?? 0.0));
    final double usCurrentProfitKrw = usCurrentProfitUsd * (usExchangeRate ?? 1.0);
    final double krCurrentProfit = krBalanceData.fold<double>(0.0, (sum, item) => sum + ((item['currency'] == 'KRW' ? (item['profit_loss'] as double?) : 0.0) ?? 0.0));

    final double totalProfitKrw = usCurrentProfitKrw + krCurrentProfit;

    final List<ChartData> allStocksChartData = [];

    // Add US stocks
    for (var item in usBalanceData) {
      final double profitLossUsd = (item['profit_loss_usd'] as num?)?.toDouble() ?? 0.0;
      final double profitLossKrw = profitLossUsd * (usExchangeRate ?? 1.0);
      allStocksChartData.add(ChartData(item['name'] as String, profitLossKrw / 10000));
    }

    // Add KR stocks
    for (var item in krBalanceData) {
      if (item['currency'] == 'KRW') {
        final double profitLossKrw = (item['profit_loss'] as double?) ?? 0.0;
        allStocksChartData.add(ChartData(item['name'] as String, profitLossKrw / 10000));
      }
    }

    // Sort data for chart (ascending for stacked bar segments: smaller profit on left, larger on right)
    final List<ChartData> sortedChartData = List.from(allStocksChartData)
      ..sort((a, b) => a.value.compareTo(b.value));

    // Sort data for table (ascending to match chart order)
    final List<ChartData> sortedTableData = List.from(allStocksChartData)
      ..sort((a, b) => a.value.compareTo(b.value));

    // Use a generic currency formatter for display
    final NumberFormat currencyFormatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('홈 화면'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '종목별 평가 손익',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${currencyFormatter.format(totalProfitKrw / 10000)}만원',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: totalProfitKrw >= 0 ? Colors.green : Colors.red),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 150, // Adjust height as needed
                        child: SfCartesianChart(
                          primaryXAxis: CategoryAxis(),
                          primaryYAxis: NumericAxis(
                            numberFormat: currencyFormatter,
                            title: AxisTitle(text: '평가 손익 (만원)'),
                          ),
                          series: <CartesianSeries>[
                            StackedBarSeries<ChartData, String>(
                              dataSource: sortedChartData,
                              xValueMapper: (ChartData data, _) => '총 평가 손익',
                              yValueMapper: (ChartData data, _) => data.value,
                              groupName: 'profitGroup',
                              name: '총 평가 손익',
                              pointColorMapper: (ChartData data, _) => _getColorForStock(data.category), // Assign unique color per segment
                              dataLabelSettings: DataLabelSettings(
                                isVisible: false,
                                builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                                  return Text('${data.category}\n${currencyFormatter.format(data.value)}만원');
                                },
                              ),
                            ),
                          ],
                          tooltipBehavior: TooltipBehavior(enable: true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Table for stock-specific profit/loss
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('종목')),
                  DataColumn(label: Text('평가 손익 (만원)'), numeric: true),
                ],
                rows: sortedTableData.map((data) {
                  final Color valueColor = data.value >= 0 ? Colors.green : Colors.red;
                  return DataRow(
                    cells: [
                      DataCell(Text(data.category)),
                      DataCell(Text(
                        '${currencyFormatter.format(data.value)}만원',
                        style: TextStyle(color: valueColor),
                      )),
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
  Color _getColorForStock(String stockName) {
    final int hash = stockName.hashCode;
    return Color.fromARGB(255, (hash * 123) % 256, (hash * 456) % 256, (hash * 789) % 256);
  }
}

class ChartData {
  ChartData(this.category, this.value);
  final String category;
  final double value;
}