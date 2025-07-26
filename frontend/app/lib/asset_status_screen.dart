import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'responsive_text.dart';

class AssetStatusScreen extends StatefulWidget {
  final List<dynamic> usBalanceData;
  final List<dynamic> krBalanceData;

  const AssetStatusScreen({
    super.key,
    required this.usBalanceData,
    required this.krBalanceData,
  });

  @override
  State<AssetStatusScreen> createState() => _AssetStatusScreenState();
}

class _PieData {
  _PieData(this.x, this.y, this.color);
  final String x;
  final double y;
  final Color color;
}

class _AssetStatusScreenState extends State<AssetStatusScreen> {
  String _selectedCurrency = 'USD';
  Map<String, dynamic>? _balanceData;
  double _exchangeRate = 0.0;

  @override
  void initState() {
    super.initState();
    _updateBalanceData();
  }

  @override
  void didUpdateWidget(covariant AssetStatusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateBalanceData();
  }

  void _updateBalanceData() {
    if (_selectedCurrency == 'USD') {
      _balanceData = {
        'stocks': widget.usBalanceData,
        'cash': {
          'usd': widget.usBalanceData.firstWhere((stock) => stock['ticker'] == 'USD', orElse: () => {'valuation_usd': 0.0})['valuation_usd'],
          'krw': 0.0, // Not directly available in US balance data
          'usd_in_krw': 0.0, // Not directly available in US balance data
        },
        'exchange_rate': widget.usBalanceData.firstWhere((stock) => stock['ticker'] == 'USD', orElse: () => {'exchange_rate': 0.0})['exchange_rate'],
      };
    } else { // KRW
      _balanceData = {
        'stocks': widget.krBalanceData,
        'cash': {
          'krw': widget.krBalanceData.firstWhere((stock) => stock['ticker'] == 'KRW', orElse: () => {'valuation': 0.0})['valuation'],
          'usd': 0.0, // Not directly available in KR balance data
          'usd_in_krw': widget.krBalanceData.firstWhere((stock) => stock['ticker'] == 'USD', orElse: () => {'valuation': 0.0})['valuation'],
        },
        'exchange_rate': widget.krBalanceData.firstWhere((stock) => stock['ticker'] == 'KRW', orElse: () => {'exchange_rate': 0.0})['exchange_rate'],
      };
    }
    _exchangeRate = (_balanceData!['exchange_rate'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final usdCurrencyFormat = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          // 데이터는 main.dart에서 관리하므로 여기서는 새로고침 로직이 필요 없음
          // 필요하다면 main.dart의 _fetchData를 다시 호출하도록 구현
        },
        child: _balanceData == null
            ? const Center(child: Text('데이터를 불러오는데 실패했습니다.'))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTotalAssetSection(currencyFormat, usdCurrencyFormat),
                    const SizedBox(height: 12),
                    _buildCashSection(currencyFormat, usdCurrencyFormat),
                    const SizedBox(height: 12),
                    _buildStockSection(currencyFormat, usdCurrencyFormat),
                    const Divider(),
                    _buildPieChart(currencyFormat, usdCurrencyFormat),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTotalAssetSection(NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final cash = _balanceData!['cash'];
    final stocks = _balanceData!['stocks'] as List;
    final theme = Theme.of(context);

    double totalCash;
    double totalStockValuation;

    if (_selectedCurrency == 'KRW') {
      totalCash = (cash['krw'] ?? 0).toDouble() + (cash['usd_in_krw'] ?? 0).toDouble();
      totalStockValuation = stocks.fold<double>(0.0, (sum, stock) => sum + (stock['valuation'] as num).toDouble());
    } else { // USD
      totalCash = (cash['usd'] ?? 0.0).toDouble();
      totalStockValuation = stocks.where((s) => s['currency'] == 'USD').fold<double>(0.0, (sum, stock) => sum + (stock['valuation_usd'] as num).toDouble());
    }

    final totalAsset = totalCash + totalStockValuation;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('총 자산', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 20), color: theme.colorScheme.onSurface)),
                    if (_selectedCurrency == 'KRW' && _exchangeRate > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text('(환율: ${_exchangeRate.toStringAsFixed(2)}원)', style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: _selectedCurrency == 'USD',
                        onChanged: (value) {
                          setState(() {
                            _selectedCurrency = value ? 'KRW' : 'USD';
                            _updateBalanceData(); // 통화 변경 시 데이터 업데이트
                          });
                        },
                      ),
                    ),
                    Text('USD', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _selectedCurrency == 'KRW' ? currencyFormat.format(totalAsset) : usdCurrencyFormat.format(totalAsset),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 24), color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashSection(NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final cash = _balanceData!['cash'];
    final theme = Theme.of(context);

    if (_selectedCurrency == 'KRW') {
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
              Text('예수금 상세', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
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
    } else { // USD
      final usd = cash['usd'] ?? 0.0;
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('예수금 상세', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
              ListTile(
                visualDensity: VisualDensity.compact,
                title: Text('총 달러 예수금', style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: theme.colorScheme.onSurface)),
                trailing: Text(usdCurrencyFormat.format(usd), style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: theme.colorScheme.onSurface)),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildStockSection(NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final stocks = _balanceData!['stocks'] as List;
    final theme = Theme.of(context);

    if (_selectedCurrency == 'KRW') {
      if (stocks.isEmpty) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(child: Text('보유 주식이 없습니다.', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))),
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
              Text('주식 상세', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
              const Divider(),
              ...(() {
                final sortedStocks = stocks.toList();
                sortedStocks.sort((a, b) => (b['valuation'] as num).compareTo(a['valuation'] as num));
                return sortedStocks.map((stock) => _buildStockTile(stock, currencyFormat, usdCurrencyFormat)).toList();
              })(),
            ],
          ),
        ),
      );
    } else { // USD
      final usdStocks = stocks.where((s) => s['currency'] == 'USD').toList();
      if (usdStocks.isEmpty) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('주식 상세', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
                Center(child: Text('보유 미국 주식이 없습니다.', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))),
              ],
            ),
          ),
        );
      }
      final sortedUsdStocks = usdStocks.toList();
      sortedUsdStocks.sort((a, b) => (b['valuation_usd'] as num).compareTo(a['valuation_usd'] as num));
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('주식 상세', style: theme.textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
              const Divider(),
              ...sortedUsdStocks.map((stock) => _buildStockTile(stock, currencyFormat, usdCurrencyFormat)).toList(),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildPieChart(NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final cash = _balanceData!['cash'];
    final stocks = _balanceData!['stocks'] as List;
    final theme = Theme.of(context);
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

    if (_selectedCurrency == 'KRW') {
      final totalCash = (cash['krw'] ?? 0) + (cash['usd_in_krw'] ?? 0);
      chartData.add(_PieData('예수금', totalCash.toDouble(), theme.colorScheme.surfaceVariant));

      for (int i = 0; i < stocks.length; i++) {
        final stock = stocks[i];
        chartData.add(_PieData(stock['name'], (stock['valuation'] as num).toDouble(), colorPalette[i % colorPalette.length]));
      }

      totalValue = chartData.fold(0, (sum, d) => sum + d.y);

    } else { // USD
      final totalCash = cash['usd'] ?? 0.0;
      chartData.add(_PieData('예수금', totalCash, theme.colorScheme.surfaceVariant));

      final usdStocks = stocks.where((s) => s['currency'] == 'USD').toList();
      for (int i = 0; i < usdStocks.length; i++) {
        final stock = usdStocks[i];
        chartData.add(_PieData(stock['name'], (stock['valuation_usd'] as num).toDouble(), colorPalette[i % colorPalette.length]));
      }
      totalValue = chartData.fold(0, (sum, d) => sum + d.y);
    }
    
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
            '총 자산: ${_selectedCurrency == 'KRW' ? currencyFormat.format(totalValue) : usdCurrencyFormat.format(totalValue)}',
            style: theme.textTheme.titleLarge?.copyWith(fontSize: getResponsiveFontSize(context, 22), color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _buildStockTile(Map<String, dynamic> stock, NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final isUsd = stock['currency'] == 'USD';
    final theme = Theme.of(context);

    if (_selectedCurrency == 'KRW') {
      final valuation = stock['valuation'];
      final profitLoss = stock['profit_loss'];
      final profitLossRatio = stock['profit_loss_ratio'];

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        elevation: 2,
        child: ExpansionTile(
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
                  style: TextStyle(color: profitLoss >= 0 ? Colors.greenAccent[400] : Colors.redAccent[400], fontSize: getResponsiveFontSize(context, 14)),
                ),
              ],
            ),
          ),
          children: [
            ListTile(
              title: Text('평균 단가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
              trailing: Text(isUsd ? usdCurrencyFormat.format(stock['average_price']) : currencyFormat.format(stock['average_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))
            ),
            ListTile(
              title: Text('현재가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
              trailing: Text(isUsd ? usdCurrencyFormat.format(stock['current_price']) : currencyFormat.format(stock['current_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))
            ),
            ListTile(
              title: Text('평가 손익', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
              trailing: Text(
                isUsd ? '${usdCurrencyFormat.format(stock['profit_loss_usd'])} (${currencyFormat.format(profitLoss)})' : currencyFormat.format(profitLoss),
                style: TextStyle(color: profitLoss >= 0 ? Colors.greenAccent[400] : Colors.redAccent[400], fontSize: getResponsiveFontSize(context, 14)),
              ),
            ),
          ],
        ),
      );
    } else { // USD
      final valuation = stock['valuation_usd'];
      final profitLoss = stock['profit_loss_usd'];
      final profitLossRatio = stock['profit_loss_ratio'];

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        elevation: 2,
        child: ExpansionTile(
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
                    usdCurrencyFormat.format(valuation),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface),
                  ),
                ),
                Text(
                  '${profitLossRatio.toStringAsFixed(2)}%',
                  style: TextStyle(color: profitLoss >= 0 ? Colors.greenAccent[400] : Colors.redAccent[400], fontSize: getResponsiveFontSize(context, 14)),
                ),
              ],
            ),
          ),
          children: [
            ListTile(
              title: Text('평균 단가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
              trailing: Text(usdCurrencyFormat.format(stock['average_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))
            ),
            ListTile(
              title: Text('현재가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
              trailing: Text(usdCurrencyFormat.format(stock['current_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))
            ),
            ListTile(
              title: Text('평가 손익', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
              trailing: Text(
                usdCurrencyFormat.format(profitLoss),
                style: TextStyle(color: profitLoss >= 0 ? Colors.greenAccent[400] : Colors.redAccent[400], fontSize: getResponsiveFontSize(context, 14)),
              ),
            ),
          ],
        ),
      );
    }
  }
}