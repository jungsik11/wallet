import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> usProfitData;
  final List<dynamic> usBalanceData;
  final Map<String, dynamic> krProfitData;
  final List<dynamic> krBalanceData;
  final Map<String, dynamic> pensionBalanceData;
  final double? usExchangeRate;

  const HomeScreen({
    Key? key,
    required this.usProfitData,
    required this.usBalanceData,
    required this.krProfitData,
    required this.krBalanceData,
    required this.pensionBalanceData,
    this.usExchangeRate,
  }) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    // Extract current estimated profit/loss for US and KR stocks
    // Assuming 'total_profit' key holds the current profit/loss
    final double usCurrentProfitUsd = widget.usBalanceData
        .where((item) => item['currency'] == 'USD') // Filter for USD stocks
        .fold<double>(0.0, (sum, item) => sum + ((item['profit_loss_usd'] as num?)?.toDouble() ?? 0.0));
    final double usCurrentProfitKrw = usCurrentProfitUsd * (widget.usExchangeRate ?? 1.0);

    final double krCurrentProfit = widget.krBalanceData
        .where((item) => item['currency'] == 'KRW') // Filter for KRW stocks
        .fold<double>(0.0, (sum, item) => sum + ((item['profit_loss'] as double?) ?? 0.0));

    // Calculate total realized profit/loss for the very top display
    double totalRealizedProfitKrw = 0.0;
    if (widget.usProfitData['yearly_total_profit'] != null) {
      (widget.usProfitData['yearly_total_profit'] as Map<String, dynamic>).forEach((year, profit) {
        totalRealizedProfitKrw += (profit as num).toDouble() * (widget.usExchangeRate ?? 1.0);
      });
    }
    if (widget.krProfitData['yearly_total_profit'] != null) {
      (widget.krProfitData['yearly_total_profit'] as Map<String, dynamic>).forEach((year, profit) {
        totalRealizedProfitKrw += (profit as num).toDouble();
      });
    }
    final double displayTotalRealizedProfit = totalRealizedProfitKrw;

    // Calculate total unrealized profit/loss for display above the chart
    final double displayTotalUnrealizedProfit = usCurrentProfitKrw + krCurrentProfit;

    // Calculate cumulative profit for the very top display
    final double displayCumulativeProfit = displayTotalRealizedProfit + displayTotalUnrealizedProfit;

    // Calculate yearly combined profit for the table
    Map<String, double> yearlyCombinedProfit = {};
    if (widget.usProfitData['yearly_total_profit'] != null) {
      (widget.usProfitData['yearly_total_profit'] as Map<String, dynamic>).forEach((year, profit) {
        yearlyCombinedProfit[year] = (yearlyCombinedProfit[year] ?? 0.0) + (profit as num).toDouble() * (widget.usExchangeRate ?? 1.0) / 10000;
      });
    }
    if (widget.krProfitData['yearly_total_profit'] != null) {
      (widget.krProfitData['yearly_total_profit'] as Map<String, dynamic>).forEach((year, profit) {
        yearlyCombinedProfit[year] = (yearlyCombinedProfit[year] ?? 0.0) + (profit as num).toDouble() / 10000;
      });
    }
    // Add current unrealized profit to the current year (2025) in the yearly table
    final String currentYear = DateTime.now().year.toString();
    yearlyCombinedProfit[currentYear] = (yearlyCombinedProfit[currentYear] ?? 0.0) + displayTotalUnrealizedProfit / 10000;

    List<String> sortedYears = yearlyCombinedProfit.keys.toList()..sort();

    final List<ChartData> allStocksChartData = [];

    // Add US stocks
    for (var item in widget.usBalanceData) {
      final double profitLossUsd = (item['profit_loss_usd'] as num?)?.toDouble() ?? 0.0;
      final double profitLossKrw = profitLossUsd * (widget.usExchangeRate ?? 1.0);
      allStocksChartData.add(ChartData(item['name'] as String, profitLossKrw / 10000));
    }

    // Add KR stocks
    for (var item in widget.krBalanceData) {
      if (item['currency'] == 'KRW') {
        final double profitLossKrw = (item['profit_loss'] as double?) ?? 0.0;
        allStocksChartData.add(ChartData(item['name'] as String, profitLossKrw / 10000));
      }
    }

    // Sort data for chart (ascending for stacked bar segments: smaller profit on left, larger on right)
    final List<ChartData> sortedChartData = List.from(allStocksChartData)
      ..sort((a, b) => a.value.compareTo(b.value));

    // Sort data for table (descending order)
    final List<ChartData> sortedTableData = List.from(allStocksChartData)
      ..sort((a, b) => b.value.compareTo(a.value));

    // Use a generic currency formatter for display
    final NumberFormat currencyFormatter = NumberFormat('#,##0.00');

    final theme = Theme.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Total Realized Profit/Loss Section
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: theme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '누적 손익',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${currencyFormatter.format(displayCumulativeProfit / 10000)}만원',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: displayCumulativeProfit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 10), // Spacing before the ExpansionTile
                    ExpansionTile(
                      title: Text(
                        '연도별 손익', // Title for the collapsible section
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                      ),
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingTextStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                            dataTextStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                            columns: [
                              const DataColumn(label: Text('구분')),
                              ...sortedYears.map((year) => DataColumn(label: Text(year))),
                            ],
                            rows: [
                              DataRow(
                                cells: [
                                  const DataCell(Text('실현 손익 (만원)')),
                                  ...sortedYears.map((year) {
                                    final double profit = yearlyCombinedProfit[year]!;
                                    final Color valueColor = profit >= 0 ? Colors.green.shade700 : Colors.red.shade700;
                                    return DataCell(Text(
                                      currencyFormatter.format(profit),
                                      style: TextStyle(color: valueColor),
                                    ));
                                  }).toList(),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Stock-specific Unrealized Profit/Loss Chart Section
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: theme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '종목별 평가 손익',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '총 평가 손익: ${currencyFormatter.format(displayTotalUnrealizedProfit / 10000)}만원',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: displayTotalUnrealizedProfit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 180, // Adjusted height for better visual balance
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
                            pointColorMapper: (ChartData data, _) => _getColorForStock(data.category),
                            dataLabelSettings: DataLabelSettings(
                              isVisible: false,
                              builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                                return Text('${data.category}${currencyFormatter.format(data.value)}만원');
                              },
                            ),
                          ),
                        ],
                        tooltipBehavior: TooltipBehavior(enable: true),
                      ),
                    ),
                    // Nested ExpansionTile for the detailed table
                    ExpansionTile(
                      title: Text(
                        '종목별 상세 평가 손익',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface), // Smaller title for nested
                      ),
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingTextStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                            dataTextStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                            columns: const [
                              DataColumn(label: Text('종목')),
                              DataColumn(label: Text('평가 손익 (만원)')),
                            ],
                            rows: sortedTableData.map((data) {
                              final Color valueColor = data.value >= 0 ? Colors.green.shade700 : Colors.red.shade700;
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
                  ],
                ),
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