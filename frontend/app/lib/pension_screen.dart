import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

// _PieData 클래스를 최상위 수준으로 이동
class _PieData {
  _PieData(this.x, this.y);
  final String x;
  final double y;
}

class PensionScreen extends StatefulWidget {
  const PensionScreen({Key? key}) : super(key: key);

  @override
  State<PensionScreen> createState() => _PensionScreenState();
}

class _PensionScreenState extends State<PensionScreen> {
  String _selectedCurrency = 'KRW'; // 통화 선택 추가
  Map<String, dynamic>? _balanceData;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchPensionData();
  }

  Future<void> _fetchPensionData() async {
    try {
      final response = await http.get(Uri.parse('http://10.0.2.2:8000/account_balance_pension'));
      if (response.statusCode == 200) {
        setState(() {
          _balanceData = jsonDecode(utf8.decode(response.bodyBytes));
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load pension data: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching pension data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    if (_balanceData == null) {
      return const Center(child: Text('연금 포트폴리오 데이터가 없습니다.'));
    }

    final holdings = _balanceData!['stocks'] as List<dynamic>?;

    final krwStocks = holdings!.where((s) => s['currency'] == 'KRW').toList();
    final totalKrwValuation = krwStocks.fold<double>(0.0, (sum, stock) => sum + (stock['valuation'] as num).toDouble());

    final List<_PieData> chartData = [];
    for (var stock in krwStocks) {
      chartData.add(_PieData(stock['name'], (stock['valuation'] as num).toDouble()));
    }

    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final usdCurrencyFormat = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    final percentFormat = NumberFormat.decimalPercentPattern(decimalDigits: 2);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('연금 자산 구성', style: Theme.of(context).textTheme.titleLarge),
            if (chartData.isNotEmpty)
              SizedBox(
                height: 300,
                child: SfCircularChart(
                  title: ChartTitle(text: '총 평가금액: ${currencyFormat.format(totalKrwValuation)}'),
                  legend: const Legend(isVisible: true, overflowMode: LegendItemOverflowMode.wrap),
                  series: <CircularSeries<_PieData, String>>[
                    PieSeries<_PieData, String>(
                      dataSource: chartData,
                      xValueMapper: (_PieData data, _) => data.x,
                      yValueMapper: (_PieData data, _) => data.y,
                      dataLabelMapper: (data, _) => '${(data.y / totalKrwValuation * 100).toStringAsFixed(1)}%',
                      dataLabelSettings: const DataLabelSettings(isVisible: true),
                    )
                  ],
                ),
              )
            else
              const SizedBox(height: 300, child: Center(child: Text("보유 자산이 없습니다."))),
            const SizedBox(height: 20),
            Text('연금 보유 종목 현황', style: Theme.of(context).textTheme.titleLarge),
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
                rows: holdings!.map((holding) {
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