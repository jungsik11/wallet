import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'responsive_text.dart';

class AssetStatusScreen extends StatefulWidget {
  const AssetStatusScreen({super.key});

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
  String _selectedCurrency = 'KRW';
  Map<String, dynamic>? _balanceData;
  bool _isLoading = true;
  double _exchangeRate = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchBalance();
  }

  Future<void> _fetchBalance() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:8000/account_balance'));
      if (response.statusCode == 200) {
        setState(() {
          _balanceData = jsonDecode(utf8.decode(response.bodyBytes));
          _exchangeRate = (_balanceData!['exchange_rate'] as num?)?.toDouble() ?? 0.0;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        // Handle error
        print('Failed to load balance');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error
      print('Error fetching balance: $e');
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final usdCurrencyFormat = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    return RefreshIndicator(
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          children: [
                            if (_selectedCurrency == 'KRW' && _exchangeRate > 0)
                              Text('환율: ${_exchangeRate.toStringAsFixed(2)}원', style: TextStyle(fontSize: getResponsiveFontSize(context, 12))),
                            const Spacer(),
                            Transform.scale(
                              scale: 0.7,
                              child: Switch(
                                value: _selectedCurrency == 'KRW',
                                onChanged: (value) {
                                  setState(() {
                                    _selectedCurrency = value ? 'KRW' : 'USD';
                                  });
                                },
                              ),
                            ),
                            const Text('USD', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      _buildPieChart(currencyFormat, usdCurrencyFormat),
                      const Divider(),
                      _buildCashSection(currencyFormat, usdCurrencyFormat),
                      const SizedBox(height: 12),
                      _buildStockSection(currencyFormat, usdCurrencyFormat),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCashSection(NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final cash = _balanceData!['cash'];

    if (_selectedCurrency == 'KRW') {
      final krw = cash['krw'] ?? 0;
      final usdInKrw = cash['usd_in_krw'] ?? 0;
      final totalCash = krw + usdInKrw;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 2.0),
            child: Text('예수금', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 20))),
          ),
          ListTile(
            visualDensity: VisualDensity.compact,
            title: Text('총 예수금', style: TextStyle(fontSize: getResponsiveFontSize(context, 16))),
            trailing: Text(currencyFormat.format(totalCash), style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16))),
          ),
          ListTile(
            visualDensity: VisualDensity.compact,
            title: Text('원화', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
            trailing: Text(currencyFormat.format(krw), style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
          ),
          ListTile(
            visualDensity: VisualDensity.compact,
            title: Text('달러', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
            trailing: Text(currencyFormat.format(usdInKrw), style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
          ),
        ],
      );
    } else { // USD
      final usd = cash['usd'] ?? 0.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 2.0),
            child: Text('예수금', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 20))),
          ),
          ListTile(
            visualDensity: VisualDensity.compact,
            title: Text('총 달러 예수금', style: TextStyle(fontSize: getResponsiveFontSize(context, 16))),
            trailing: Text(usdCurrencyFormat.format(usd), style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16))),
          ),
        ],
      );
    }
  }

  Widget _buildStockSection(NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final stocks = _balanceData!['stocks'] as List;

    if (_selectedCurrency == 'KRW') {
      if (stocks.isEmpty) {
        return Center(child: Text('보유 주식이 없습니다.', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))));
      }
      final totalValuation = stocks.fold<num>(0, (sum, stock) => sum + (stock['valuation'] as num));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
            child: Text('주식', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 20))),
          ),
          ListTile(
            title: Text('총 주식 평가액', style: TextStyle(fontSize: getResponsiveFontSize(context, 16))),
            trailing: Text(currencyFormat.format(totalValuation), style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16))),
          ),
          const Divider(),
          ...stocks.map((stock) => _buildStockTile(stock, currencyFormat, usdCurrencyFormat)),
        ],
      );
    } else { // USD
      final usdStocks = stocks.where((s) => s['currency'] == 'USD').toList();
      if (usdStocks.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
              child: Text('주식', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 20))),
            ),
            Center(child: Text('보유 미국 주식이 없습니다.', style: TextStyle(fontSize: getResponsiveFontSize(context, 14)))),
          ],
        );
      }
      final totalUsdValuation = usdStocks.fold<double>(0.0, (sum, stock) => sum + (stock['valuation_usd'] as double));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
            child: Text('주식', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: getResponsiveFontSize(context, 20))),
          ),
          ListTile(
            title: Text('총 주식 평가액', style: TextStyle(fontSize: getResponsiveFontSize(context, 16))),
            trailing: Text(usdCurrencyFormat.format(totalUsdValuation), style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16))),
          ),
          const Divider(),
          ...usdStocks.map((stock) => _buildStockTile(stock, currencyFormat, usdCurrencyFormat)),
        ],
      );
    }
  }

  Widget _buildPieChart(NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final cash = _balanceData!['cash'];
    final stocks = _balanceData!['stocks'] as List;
    final List<Color> colorPalette = [
      Colors.orangeAccent[100]!,
      Colors.lightGreenAccent[400]!,
      Colors.redAccent[100]!,
      Colors.purpleAccent[100]!,
      Colors.tealAccent[100]!,
      Colors.cyanAccent[400]!,
      Colors.indigoAccent[100]!,
      Colors.pinkAccent[100]!,
      Colors.amberAccent[100]!,
      Colors.lightBlueAccent[100]!
    ];

    double totalValue;
    List<_PieData> chartData = [];

    if (_selectedCurrency == 'KRW') {
      final totalCash = (cash['krw'] ?? 0) + (cash['usd_in_krw'] ?? 0);
      chartData.add(_PieData('예수금', totalCash.toDouble(), Colors.blueGrey[300]!));

      for (int i = 0; i < stocks.length; i++) {
        final stock = stocks[i];
        chartData.add(_PieData(stock['name'], (stock['valuation'] as num).toDouble(), colorPalette[i % colorPalette.length]));
      }

      totalValue = chartData.fold(0, (sum, d) => sum + d.y);

    } else { // USD
      final totalCash = cash['usd'] ?? 0.0;
      chartData.add(_PieData('예수금', totalCash, Colors.blueGrey[300]!));

      final usdStocks = stocks.where((s) => s['currency'] == 'USD').toList();
      for (int i = 0; i < usdStocks.length; i++) {
        final stock = usdStocks[i];
        chartData.add(_PieData(stock['name'], (stock['valuation_usd'] as num).toDouble(), colorPalette[i % colorPalette.length]));
      }
      totalValue = chartData.fold(0, (sum, d) => sum + d.y);
    }
    
    chartData.removeWhere((d) => d.y <= 0);

    if (chartData.isEmpty) {
      return const SizedBox(height: 250, child: Center(child: Text("자산이 없습니다.")));
    }

    return Column(
      children: [
        SizedBox(
          height: 250,
          child: SfCircularChart(
            legend: const Legend(isVisible: true, overflowMode: LegendItemOverflowMode.wrap, position: LegendPosition.bottom),
            series: <CircularSeries<_PieData, String>>[
              PieSeries<_PieData, String>(
                dataSource: chartData,
                xValueMapper: (_PieData data, _) => data.x,
                yValueMapper: (_PieData data, _) => data.y,
                pointColorMapper: (_PieData data, _) => data.color,
                dataLabelMapper: (data, _) => '${(data.y / totalValue * 100).toStringAsFixed(1)}%',
                dataLabelSettings: const DataLabelSettings(isVisible: true, labelPosition: ChartDataLabelPosition.outside),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            '총 자산: ${_selectedCurrency == 'KRW' ? currencyFormat.format(totalValue) : usdCurrencyFormat.format(totalValue)}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: getResponsiveFontSize(context, 22)),
          ),
        ),
      ],
    );
  }

  Widget _buildStockTile(Map<String, dynamic> stock, NumberFormat currencyFormat, NumberFormat usdCurrencyFormat) {
    final isUsd = stock['currency'] == 'USD';

    if (_selectedCurrency == 'KRW') {
      final valuation = stock['valuation'];
      final profitLoss = stock['profit_loss'];
      final profitLossRatio = stock['profit_loss_ratio'];

      return ExpansionTile(
        title: Text(stock['name'], style: TextStyle(fontSize: getResponsiveFontSize(context, 16))),
        subtitle: Text('${stock['ticker']} ・ ${stock['quantity']}주', style: TextStyle(fontSize: getResponsiveFontSize(context, 12))),
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16)),
                ),
              ),
              Text(
                '${profitLossRatio.toStringAsFixed(2)}%',
                style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red, fontSize: getResponsiveFontSize(context, 14)),
              ),
            ],
          ),
        ),
        children: [
          ListTile(
            title: Text('평균 단가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
            trailing: Text(isUsd ? usdCurrencyFormat.format(stock['average_price']) : currencyFormat.format(stock['average_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14)))
          ),
          ListTile(
            title: Text('현재가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
            trailing: Text(isUsd ? usdCurrencyFormat.format(stock['current_price']) : currencyFormat.format(stock['current_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14)))
          ),
          ListTile(
            title: Text('평가 손익', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
            trailing: Text(
              isUsd ? '${usdCurrencyFormat.format(stock['profit_loss_usd'])} (${currencyFormat.format(profitLoss)})' : currencyFormat.format(profitLoss),
              style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red, fontSize: getResponsiveFontSize(context, 14)),
            ),
          ),
        ],
      );
    } else { // USD
      final valuation = stock['valuation_usd'];
      final profitLoss = stock['profit_loss_usd'];
      final profitLossRatio = stock['profit_loss_ratio'];

      return ExpansionTile(
        title: Text(stock['name'], style: TextStyle(fontSize: getResponsiveFontSize(context, 16))),
        subtitle: Text('${stock['ticker']} ・ ${stock['quantity']}주', style: TextStyle(fontSize: getResponsiveFontSize(context, 12))),
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16)),
                ),
              ),
              Text(
                '${profitLossRatio.toStringAsFixed(2)}%',
                style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red, fontSize: getResponsiveFontSize(context, 14)),
              ),
            ],
          ),
        ),
        children: [
          ListTile(
            title: Text('평균 단가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
            trailing: Text(usdCurrencyFormat.format(stock['average_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14)))
          ),
          ListTile(
            title: Text('현재가', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
            trailing: Text(usdCurrencyFormat.format(stock['current_price']), style: TextStyle(fontSize: getResponsiveFontSize(context, 14)))
          ),
          ListTile(
            title: Text('평가 손익', style: TextStyle(fontSize: getResponsiveFontSize(context, 14))),
            trailing: Text(
              usdCurrencyFormat.format(profitLoss),
              style: TextStyle(color: profitLoss >= 0 ? Colors.green : Colors.red, fontSize: getResponsiveFontSize(context, 14)),
            ),
          ),
        ],
      );
    }
  }
}
