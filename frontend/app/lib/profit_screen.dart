import 'package:flutter/material.dart';

import 'profit_response.dart';
import 'yearly_profit_screen.dart';

class ProfitScreen extends StatefulWidget {
  final String country;
  final Map<String, dynamic> profitData;
  final Map<String, double> currentPrices;

  const ProfitScreen({
    Key? key,
    required this.country,
    required this.profitData,
    required this.currentPrices,
  }) : super(key: key);

  @override
  _ProfitScreenState createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  late ProfitResponse profitResponse;

  @override
  void initState() {
    super.initState();
    _processProfitData();
  }

  @override
  void didUpdateWidget(covariant ProfitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.country != oldWidget.country ||
        widget.profitData != oldWidget.profitData ||
        widget.currentPrices != oldWidget.currentPrices) {
      _processProfitData();
    }
  }

  void _processProfitData() {
    setState(() {
      profitResponse = ProfitResponse.fromJson(widget.profitData);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year.toString();
    final currentYearProfit = profitResponse.yearlyTotalProfit[currentYear] ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('수익 현황'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '올해 총 실현손익: ${currentYearProfit.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        YearlyProfitScreen(profitResponse: profitResponse),
                  ),
                );
              },
              child: const Text('상세보기'),
            ),
            DataTable(
              columns: const [
                DataColumn(label: Text('종목')),
                DataColumn(label: Text('평가손익')),
                DataColumn(label: Text('현재가')),
                DataColumn(label: Text('평균단가')),
                DataColumn(label: Text('보유수량')),
                DataColumn(label: Text('올해실현손익')),
              ],
              rows: profitResponse.stocks.where((stockMap) {
                final stockHolding = stockMap.values.first;
                return stockHolding.holdings['total'] > 0;
              }).map((stockMap) {
                final ticker = stockMap.keys.first;
                final stockHolding = stockMap.values.first;
                final stockCurrentYearProfit =
                    stockHolding.yearlyProfit[currentYear] ?? 0.0;
                final currentPrice = widget.currentPrices[ticker] ?? 0.0;
                final avgPrice = stockHolding.holdings['avg_price'] ?? 0.0;
                final total = stockHolding.holdings['total'] ?? 0.0;
                final valuation = (currentPrice - avgPrice) * total;
                return DataRow(
                  cells: [
                    DataCell(Text(ticker)),
                    DataCell(Text(valuation.toStringAsFixed(2))),
                    DataCell(Text(currentPrice.toString())),
                    DataCell(Text(avgPrice.toString())),
                    DataCell(Text(total.toString())),
                    DataCell(
                        Text(stockCurrentYearProfit.toStringAsFixed(2))),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
