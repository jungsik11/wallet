import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'profit_response.dart';
import 'yearly_profit_screen.dart';
import 'responsive_text.dart'; // Add this import

class ProfitScreen extends StatefulWidget {
  final Map<String, dynamic> usProfitData;
  final List<dynamic> usBalanceData;
  final Map<String, dynamic> krProfitData;
  final List<dynamic> krBalanceData;
  final double? usExchangeRate; // Add this
  final double? krExchangeRate; // Add this

  const ProfitScreen({
    Key? key,
    required this.usProfitData,
    required this.usBalanceData,
    required this.krProfitData,
    required this.krBalanceData,
    this.usExchangeRate, // Make optional
    this.krExchangeRate, // Make optional
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

      // Create profit responses for both US and KR
      final usProfitResponse = ProfitResponse.fromJson(widget.usProfitData);
      final krProfitResponse = ProfitResponse.fromJson(widget.krProfitData);

      final profitResponseForSelectedCountry = _selectedCountry == 'US' ? usProfitResponse : krProfitResponse;
      final balanceDataForSelectedCountry = _selectedCountry == 'US' ? widget.usBalanceData : widget.krBalanceData;

      final currentYearProfit = profitResponseForSelectedCountry.yearlyTotalProfit[currentYear] ?? 0.0;
      final currencyUnit = _selectedCountry == 'KR' ? '(만원)' : '(USD)';

      final sortedBalanceData = List.from(balanceDataForSelectedCountry)
        .where((holding) => holding['market'] != 'CASH') // Filter out cash entries
        .where((holding) => !(_selectedCountry == 'KR' && holding['currency'] == 'USD')) // Filter out USD stocks when KR is selected
        .toList()
        ..sort((a, b) {
        final aIsUsd = a['currency'] == 'USD';
        final bIsUsd = b['currency'] == 'USD';

        double aProfitLoss;
        double bProfitLoss;

        if (_selectedCountry == 'US') {
          aProfitLoss = (a['profit_loss_usd'] as num?)?.toDouble() ?? 0.0;
          bProfitLoss = (b['profit_loss_usd'] as num?)?.toDouble() ?? 0.0;
        } else { // KR
          aProfitLoss = (a['profit_loss'] as num?)?.toDouble() ?? 0.0;
          bProfitLoss = (b['profit_loss'] as num?)?.toDouble() ?? 0.0;
        }

        return bProfitLoss.compareTo(aProfitLoss); // Descending order
      });

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              color: theme.cardColor, // Apply theme card color
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      '올해 총 실현손익',
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface, fontSize: getResponsiveFontSize(context, 18)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatCurrency(currentYearProfit),
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontSize: getResponsiveFontSize(context, 24)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => YearlyProfitScreen(
                                  profitResponse: profitResponseForSelectedCountry, // Use the correct profit response
                                  country: _selectedCountry,
                                ),
                              ),
                            );
                          },
                          child: Text('연도별 상세 보기', style: TextStyle(color: theme.colorScheme.secondary, fontSize: getResponsiveFontSize(context, 14))), // Apply theme secondary color
                        ),
                        if (_selectedCountry == 'KR' && widget.krExchangeRate != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              '(환율: ${NumberFormat.currency(locale: 'ko_KR', symbol: '₩', decimalDigits: 2).format(widget.krExchangeRate!)}/USD)',
                              style: TextStyle(fontSize: getResponsiveFontSize(context, 12), color: theme.colorScheme.onSurface.withOpacity(0.7)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontSize: getResponsiveFontSize(context, 14)), // Apply theme onSurface color
                dataTextStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface, fontSize: getResponsiveFontSize(context, 12)), // Apply theme onSurface color
                columns: [
                  DataColumn(label: Text('종목')),
                  DataColumn(label: Text('평가손익\n$currencyUnit'), numeric: true),
                  DataColumn(label: Text('현재가\n$currencyUnit'), numeric: true),
                  DataColumn(label: Text('평단가\n$currencyUnit'), numeric: true),
                  DataColumn(label: Text('수량'), numeric: true),
                  DataColumn(label: Text('실현손익\n$currencyUnit'), numeric: true),
                ],
                rows: sortedBalanceData.map((holding) {
                  final ticker = holding['ticker'] as String;
                  final isUsdStock = holding['currency'] == 'USD';

                  double unrealizedPnl;
                  double currentPrice;
                  double avgPrice;
                  double realizedPnl;

                  StockHolding? stockProfitData;

                  // Determine which profitResponse to use for realized PnL
                  if (isUsdStock) {
                    // For USD stocks, always look in US profit data
                    for (var stockMap in usProfitResponse.stocks) { // Use usProfitResponse
                      if (stockMap.keys.first == ticker) {
                        stockProfitData = stockMap.values.first;
                        break;
                      }
                    }
                  } else {
                    // For KRW stocks, always look in KR profit data
                    for (var stockMap in krProfitResponse.stocks) { // Use krProfitResponse
                      if (stockMap.keys.first == ticker) {
                        stockProfitData = stockMap.values.first;
                        break;
                      }
                    }
                  }

                  if (_selectedCountry == 'US') {
                    unrealizedPnl = (holding['profit_loss_usd'] as num?)?.toDouble() ?? 0.0;
                    currentPrice = (holding['current_price'] as num?)?.toDouble() ?? 0.0;
                    avgPrice = (holding['average_price'] as num?)?.toDouble() ?? 0.0;
                    realizedPnl = (stockProfitData?.yearlyProfit[currentYear] as num?)?.toDouble() ?? 0.0;
                  } else { // _selectedCountry == 'KR'
                    unrealizedPnl = (holding['profit_loss'] as num?)?.toDouble() ?? 0.0;
                    if (isUsdStock && widget.krExchangeRate != null) {
                      currentPrice = ((holding['current_price'] as num?)?.toDouble() ?? 0.0) * widget.krExchangeRate!;
                      avgPrice = ((holding['average_price'] as num?)?.toDouble() ?? 0.0) * widget.krExchangeRate!;
                      realizedPnl = (stockProfitData?.yearlyProfit[currentYear] as num?)?.toDouble() ?? 0.0;
                      realizedPnl = realizedPnl * widget.krExchangeRate!;
                    } else {
                      currentPrice = (holding['current_price'] as num?)?.toDouble() ?? 0.0;
                      avgPrice = (holding['average_price'] as num?)?.toDouble() ?? 0.0;
                      realizedPnl = (stockProfitData?.yearlyProfit[currentYear] as num?)?.toDouble() ?? 0.0;
                    }
                  }

                  final quantity = (holding['quantity'] as num?)?.toInt() ?? 0;
                  final valuationColor = unrealizedPnl > 0 ? Colors.greenAccent[400] : (unrealizedPnl < 0 ? Colors.redAccent[400] : theme.colorScheme.onSurface.withOpacity(0.7));

                  return DataRow(
                    cells: [
                      DataCell(Text(ticker)),
                      DataCell(Text(_formatCurrency(unrealizedPnl), style: TextStyle(color: valuationColor, fontSize: getResponsiveFontSize(context, 12)))),
                      DataCell(Text(_formatCurrency(currentPrice), style: TextStyle(fontSize: getResponsiveFontSize(context, 12)))),
                      DataCell(Text(_formatCurrency(avgPrice), style: TextStyle(fontSize: getResponsiveFontSize(context, 12)))),
                      DataCell(Text(quantity.toString(), style: TextStyle(fontSize: getResponsiveFontSize(context, 12)))),
                      DataCell(Text(_formatCurrency(realizedPnl), style: TextStyle(fontSize: getResponsiveFontSize(context, 12)))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor, // Apply theme background color
      body: Column(
        children: [
          const SizedBox(height: kToolbarHeight), // Add this line
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Transform.scale(
                  scale: 0.7,
                  child: Switch(
                    value: _selectedCountry == 'US',
                    onChanged: (value) {
                      setState(() {
                        _selectedCountry = value ? 'US' : 'KR';
                      });
                    },
                  ),
                ),
                Text('USD', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)), // Apply theme onSurface color
              ],
            ),
          ),
          Expanded(child: buildDataView()),
        ],
      ),
    );
  }
}