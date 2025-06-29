import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'profit_response.dart';
import 'yearly_profit_screen.dart';

class ProfitScreen extends StatefulWidget {
  final Map<String, dynamic> usProfitData;
  final List<dynamic> usBalanceData;
  final Map<String, dynamic> krProfitData;
  final List<dynamic> krBalanceData;

  const ProfitScreen({
    Key? key,
    required this.usProfitData,
    required this.usBalanceData,
    required this.krProfitData,
    required this.krBalanceData,
  }) : super(key: key);

  @override
  _ProfitScreenState createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  String _selectedCountry = 'US'; // Default to US

  String _formatCurrency(double value) {
    if (_selectedCountry == 'US') {
      final format = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
      return format.format(value);
    } else {
      final format = NumberFormat('#,##0.00');
      return '${format.format(value / 10000)}만원';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildDataView() {
      final currentYear = DateTime.now().year.toString();
      final profitData = _selectedCountry == 'US' ? widget.usProfitData : widget.krProfitData;
      final balanceData = _selectedCountry == 'US' ? widget.usBalanceData : widget.krBalanceData;


      final profitResponse = ProfitResponse.fromJson(profitData);
      final currentYearProfit = profitResponse.yearlyTotalProfit[currentYear] ?? 0.0;
      final currencyUnit = _selectedCountry == 'KR' ? '(만원)' : '(USD)';

      final sortedBalanceData = List.from(balanceData)..sort((a, b) {
        final aValuation = (a['current_price'] as double? ?? 0.0) * (a['quantity'] as int? ?? 0);
        final bValuation = (b['current_price'] as double? ?? 0.0) * (b['quantity'] as int? ?? 0);
        return bValuation.compareTo(aValuation);
      });

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      '올해 총 실현손익',
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatCurrency(currentYearProfit),
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => YearlyProfitScreen(
                              profitResponse: profitResponse,
                              country: _selectedCountry,
                            ),
                          ),
                        );
                      },
                      child: const Text('연도별 상세 보기'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                dataTextStyle: theme.textTheme.bodyMedium,
                columns: [
                  const DataColumn(label: Text('종목')),
                  DataColumn(label: Text('평가손익\n$currencyUnit'), numeric: true),
                  DataColumn(label: Text('현재가\n$currencyUnit'), numeric: true),
                  DataColumn(label: Text('평단가\n$currencyUnit'), numeric: true),
                  const DataColumn(label: Text('수량'), numeric: true),
                  DataColumn(label: Text('실현손익\n$currencyUnit'), numeric: true),
                ],
                rows: sortedBalanceData.map((holding) {
                  final ticker = holding['ticker'] as String;
                  final unrealizedPnl = holding['pnl'] as double? ?? 0.0;
                  final currentPrice = holding['current_price'] as double? ?? 0.0;
                  final avgPrice = holding['avg_price'] as double? ?? 0.0;
                  final quantity = holding['quantity'] as int? ?? 0;
                  final valuationColor = unrealizedPnl > 0 ? Colors.greenAccent[400] : (unrealizedPnl < 0 ? Colors.redAccent[400] : Colors.grey);

                  StockHolding? stockProfitData;
                  for (var stockMap in profitResponse.stocks) {
                    if (stockMap.keys.first == ticker) {
                      stockProfitData = stockMap.values.first;
                      break;
                    }
                  }
                  final realizedPnl = stockProfitData?.yearlyProfit[currentYear] ?? 0.0;

                  return DataRow(
                    cells: [
                      DataCell(Text(ticker)),
                      DataCell(Text(_formatCurrency(unrealizedPnl), style: TextStyle(color: valuationColor))),
                      DataCell(Text(_formatCurrency(currentPrice))),
                      DataCell(Text(_formatCurrency(avgPrice))),
                      DataCell(Text(quantity.toString())),
                      DataCell(Text(_formatCurrency(realizedPnl))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: ToggleButtons(
            isSelected: [_selectedCountry == 'KR', _selectedCountry == 'US'],
            onPressed: (int index) {
              setState(() {
                _selectedCountry = index == 0 ? 'KR' : 'US';
              });
            },
            borderRadius: BorderRadius.circular(8.0),
            selectedColor: Colors.white,
            fillColor: Colors.blueAccent,
            color: Colors.white70,
            constraints: BoxConstraints(minWidth: 100, minHeight: 40),
            children: const [Text('국내'), Text('해외')],
          ),
        ),
        Expanded(child: buildDataView()),
      ],
    );
  }
}
