import 'package:flutter/material.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';

class CurrentPriceScreen extends StatefulWidget {
  final Function(String) onTickerSelected;
  final String ticker; // Add ticker parameter

  const CurrentPriceScreen({Key? key, required this.onTickerSelected, required this.ticker}) : super(key: key);

  @override
  _CurrentPriceScreenState createState() => _CurrentPriceScreenState();
}

class _CurrentPriceScreenState extends State<CurrentPriceScreen> {
  Map<String, dynamic>? _stockDetail;
  bool _isLoading = false;
  String? _error;

  final WalletApiService _apiService = WalletApiService();

  @override
  void initState() {
    super.initState();
    _fetchCurrentPrice();
  }

  @override
  void didUpdateWidget(covariant CurrentPriceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ticker != oldWidget.ticker) {
      _fetchCurrentPrice();
    }
  }

  Future<void> _fetchCurrentPrice() async {
    if (widget.ticker.isEmpty) {
      setState(() {
        _error = '티커가 제공되지 않았습니다.';
        _stockDetail = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final stockDetailData = await _apiService.fetchStockDetail(widget.ticker);
      if (mounted) {
        setState(() {
          _stockDetail = stockDetailData;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '현재가 데이터를 불러오는 데 실패했습니다: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String formatPrice(dynamic price) {
    if (price == null) {
      return 'N/A';
    }
    double? value = double.tryParse(price.toString());
    if (value == null) {
      return 'N/A';
    }
    final formatter = NumberFormat('#.####');
    return formatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }

    if (_stockDetail == null || _stockDetail!.isEmpty) {
      return const Center(child: Text('현재가 데이터가 없습니다.'));
    }

    final price = _stockDetail!['price'] ?? 0;
    final diff = _stockDetail!['diff'] ?? 0;
    final rate = _stockDetail!['rate'] ?? 0;
    final volume = _stockDetail!['volume'] ?? 'N/A';
    final open = _stockDetail!['open'] ?? 0;
    final high = _stockDetail!['high'] ?? 0;
    final low = _stockDetail!['low'] ?? 0;
    final name = _stockDetail!['name'] ?? 'N/A';

    final isKrw = RegExp(r'^\d{6}$').hasMatch(widget.ticker);
    final priceColor = diff > 0 ? Colors.red : (diff < 0 ? Colors.blue : Colors.grey);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            widget.ticker,
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isKrw ? NumberFormat('#,###').format(price) : formatPrice(price),
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: priceColor),
              ),
              const SizedBox(width: 8),
              Text(
                isKrw ? 'KRW' : 'USD',
                style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${diff > 0 ? '▲' : '▼'} ${isKrw ? NumberFormat('#,###').format(diff) : formatPrice(diff)}',
                style: theme.textTheme.titleMedium?.copyWith(color: priceColor),
              ),
              const SizedBox(width: 8),
              Text(
                '(${rate.toStringAsFixed(2)}%)',
                style: theme.textTheme.titleMedium?.copyWith(color: priceColor),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildDetailRow('시가', isKrw ? NumberFormat('#,###').format(open) : formatPrice(open)),
          _buildDetailRow('고가', isKrw ? NumberFormat('#,###').format(high) : formatPrice(high)),
          _buildDetailRow('저가', isKrw ? NumberFormat('#,###').format(low) : formatPrice(low)),
          _buildDetailRow('거래량', NumberFormat.compact().format(volume)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String title, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600])),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}