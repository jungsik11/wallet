import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app/responsive_text.dart';

class PensionScreen extends StatefulWidget {
  final Map<String, dynamic> pensionBalanceData;
  final Future<void> Function() onRefresh;

  const PensionScreen({super.key, required this.pensionBalanceData, required this.onRefresh});

  @override
  State<PensionScreen> createState() => _PensionScreenState();
}

class _PensionScreenState extends State<PensionScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pensionData = widget.pensionBalanceData;

    final totalPensionAssets = (pensionData['total_assets'] as num?)?.toDouble() ?? 0.0;
    final totalPensionProfitLoss = (pensionData['total_profit_loss'] as num?)?.toDouble() ?? 0.0;
    final totalPensionProfitLossRatio = (pensionData['total_profit_loss_ratio'] as num?)?.toDouble() ?? 0.0;

    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
    final percentFormat = NumberFormat.decimalPercentPattern(decimalDigits: 2);

    final profitColor = totalPensionProfitLoss >= 0 ? Colors.greenAccent[400] : Colors.redAccent[400];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
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
                      currencyFormat.format(totalPensionAssets),
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 24), color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('평가 손익', style: TextStyle(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              currencyFormat.format(totalPensionProfitLoss),
                              style: TextStyle(fontSize: getResponsiveFontSize(context, 16), color: profitColor),
                            ),
                            Text(
                              percentFormat.format(totalPensionProfitLossRatio / 100),
                              style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: profitColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('연금 상품 상세', style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onSurface)),
            const SizedBox(height: 10),
            // 연금 상품 리스트 (예시)
            // 실제 데이터에 따라 ListView.builder 등으로 구현
            if ((pensionData['products'] as List?)?.isNotEmpty ?? false)
              ...((pensionData['products'] as List).map((product) {
                final productName = product['name'] ?? 'N/A';
                final productValuation = (product['valuation'] as num?)?.toDouble() ?? 0.0;
                final productProfitLoss = (product['profit_loss'] as num?)?.toDouble() ?? 0.0;
                final productProfitLossRatio = (product['profit_loss_ratio'] as num?)?.toDouble() ?? 0.0;
                final productProfitColor = productProfitLoss >= 0 ? Colors.greenAccent[400] : Colors.redAccent[400];

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  elevation: 2,
                  child: ExpansionTile(
                    title: Text(productName, style: TextStyle(fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(currencyFormat.format(productValuation), style: TextStyle(fontWeight: FontWeight.bold, fontSize: getResponsiveFontSize(context, 16), color: theme.colorScheme.onSurface)),
                        Text(
                          '${productProfitLossRatio.toStringAsFixed(2)}%',
                          style: TextStyle(color: productProfitColor, fontSize: getResponsiveFontSize(context, 14)),
                        ),
                      ],
                    ),
                    children: [
                      ListTile(
                        title: Text('평가 손익', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface)),
                        trailing: Text(currencyFormat.format(productProfitLoss), style: TextStyle(color: productProfitColor, fontSize: getResponsiveFontSize(context, 14))),
                      ),
                    ],
                  ),
                );
              }).toList())
            else
              Center(child: Text('연금 상품이 없습니다.', style: TextStyle(fontSize: getResponsiveFontSize(context, 14), color: theme.colorScheme.onSurface))),
          ],
        ),
      ),
    )
    );
  }
}
