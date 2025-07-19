import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'responsive_text.dart';
import 'package:app/services/wallet_api_service.dart';

class PensionScreen extends StatefulWidget {
  const PensionScreen({super.key});

  @override
  State<PensionScreen> createState() => _PensionScreenState();
}

class _PieData {
  _PieData(this.x, this.y, this.color);
  final String x;
  final double y;
  final Color color;
}

class _PensionScreenState extends State<PensionScreen> {
  Map<String, dynamic>? _balanceData;
  bool _isLoading = true;

  final WalletApiService _apiService = WalletApiService();

  @override
  void initState() {
    super.initState();
    _fetchBalance();
  }

  Future<void> _fetchBalance() async {
    try {
      final balance = await _apiService.fetchAccountBalancePension();
      setState(() {
        _balanceData = balance;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error fetching pension balance: \$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _fetchBalance,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _balanceData == null
                ? const Center(child: Text('데이터를 불러오는데 실패했습니다.'))
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTotalPensionAssetSection(currencyFormat),
                        const SizedBox(height: 12),
                        _buildCashSection(currencyFormat),
                        const SizedBox(height: 12),
                        _buildStockSection(currencyFormat),
                        const Divider(),
                        _buildPieChart(currencyFormat, theme),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildTotalPensionAssetSection(NumberFormat currencyFormat) {
    final cash = _balanceData!['cash'];
    final stocks = _balanceData!['stocks'] as List;
    final theme = Theme.of(context);

    final totalCash = (cash['krw'] ?? 0).toDouble() + (cash['usd_in_krw'] ?? 0).toDouble();
    final totalStockValuation = stocks.fold<double>(0.0, (sum, stock) => sum + (stock['valuation'] as num).toDouble());
    final totalPensionAsset = totalCash + totalStockValuation;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('총 연금 자산', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 20), color: theme.colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text(
              currencyFormat.format(totalPensionAsset),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 24), color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashSection(NumberFormat currencyFormat) {
    final cash = _balanceData!['cash'];
    final theme = Theme.of(context);

    final krw = cash['krw'] ?? 0;
    final usdInKrw = cash['usd_in_krw'] ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('연금 예수금 상세', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
            ListTile(
              visualDensity: VisualDensity.compact,
              title: Text('원화', style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: theme.colorScheme.onSurface)),
              trailing: Text(currencyFormat.format(krw), style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: theme.colorScheme.onSurface)),
            ),
            ListTile(
              visualDensity: VisualDensity.compact,
              title: Text('달러', style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: theme.colorScheme.onSurface)),
              trailing: Text(currencyFormat.format(usdInKrw), style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: theme.colorScheme.onSurface)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockSection(NumberFormat currencyFormat) {
    final stocks = _balanceData!['stocks'] as List;
    final theme = Theme.of(context);

    if (stocks.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(child: Text('보유 연금 주식이 없습니다.', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))),
        ),
      );
    }

    final sortedStocks = stocks.toList();
    sortedStocks.sort((a, b) => (b['valuation'] as num).compareTo(a['valuation'] as num));

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('연금 주식 상세', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
            const Divider(),
            ...sortedStocks.map((stock) {
              final valuation = stock['valuation'];
              final profitLoss = stock['profit_loss'];
              final profitLossRatio = stock['profit_loss_ratio'];
              final valuationColor = profitLoss >= 0 ? Colors.greenAccent[400] : Colors.redAccent[400];

              return ExpansionTile(
                title: Text(stock['name'], style: TextStyle(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
                subtitle: Text('${stock['ticker']} ・ ${stock['quantity']}주', style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: theme.colorScheme.onSurface.withOpacity(0.7))),
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.3,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          currencyFormat.format(valuation),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface),
                        ),
                      ),
                      Text(
                        '${profitLossRatio.toStringAsFixed(2)}%',
                        style: TextStyle(color: valuationColor, fontSize: getResponsiveFontSize(context, 14)),
                      ),
                    ],
                  ),
                ),
                children: [
                  ListTile(
                    title: Text('평균 단가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
                    trailing: Text(currencyFormat.format(stock['average_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))
                  ),
                  ListTile(
                    title: Text('현재가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
                    trailing: Text(currencyFormat.format(stock['current_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))
                  ),
                  ListTile(
                    title: Text('평가 손익', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
                    trailing: Text(
                      currencyFormat.format(profitLoss),
                      style: TextStyle(color: valuationColor, fontSize: getResponsiveFontSize(context, 14)),
                    ),
                  ),
                ],
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(NumberFormat currencyFormat, ThemeData theme) {
    final cash = _balanceData!['cash'];
    final stocks = _balanceData!['stocks'] as List;
    final List<Color> colorPalette = [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      theme.colorScheme.error,
      Colors.blueGrey,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.amber,
      Colors.lightBlue,
    ];

    double totalValue;
    List<_PieData> chartData = [];

    final totalCash = (cash['krw'] ?? 0) + (cash['usd_in_krw'] ?? 0);
    chartData.add(_PieData('예수금', totalCash.toDouble(), theme.colorScheme.surfaceVariant));

    for (int i = 0; i < stocks.length; i++) {
      final stock = stocks[i];
      chartData.add(_PieData(stock['name'], (stock['valuation'] as num).toDouble(), colorPalette[i % colorPalette.length]));
    }

    totalValue = chartData.fold(0, (sum, d) => sum + d.y);
    
    chartData.removeWhere((d) => d.y <= 0);

    if (chartData.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text("자산이 없습니다.")));
    }

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: SfCircularChart(
            legend: Legend(isVisible: true, overflowMode: LegendItemOverflowMode.wrap, position: LegendPosition.bottom, textStyle: TextStyle(color: theme.colorScheme.onSurface)),
            series: <CircularSeries<_PieData, String>>[
              PieSeries<_PieData, String>(
                dataSource: chartData,
                xValueMapper: (_PieData data, _) => data.x,
                yValueMapper: (_PieData data, _) => data.y,
                pointColorMapper: (_PieData data, _) => data.color,
                dataLabelMapper: (data, _) => '${(data.y / totalValue * 100).toStringAsFixed(1)}%',
                dataLabelSettings: DataLabelSettings(isVisible: true, labelPosition: ChartDataLabelPosition.outside, textStyle: TextStyle(color: theme.colorScheme.onSurface)),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            '총 연금 자산: ${currencyFormat.format(totalValue)}',
            style: theme.textTheme.titleLarge?.copyWith(fontSize: getResponsiveFontSize(context, 22), color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}