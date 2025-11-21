import 'package:flutter/material.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:math';

class StockChartAndDetailsView extends StatefulWidget {
  final String ticker;

  const StockChartAndDetailsView({Key? key, required this.ticker}) : super(key: key);

  @override
  _StockChartAndDetailsViewState createState() => _StockChartAndDetailsViewState();
}

class _ChartData {
  _ChartData(this.x, this.open, this.high, this.low, this.close, this.volume, [this.sma5]);
  final DateTime x;
  final num open;
  final num high;
  final num low;
  final num close;
  final num volume;
  final double? sma5;


}

class _StockChartAndDetailsViewState extends State<StockChartAndDetailsView> {
  Map<String, dynamic>? _stockDetail;
  List<_ChartData> _chartData = [];
  List<_ChartData> _smaData = [];
  bool _isLoading = false;
  String? _error;
  String _selectedTimeframe = 'D';
  List<bool> _isSelected = [false, true, false]; // M, D, Y
  CrosshairBehavior? _crosshairBehavior;
  late TextEditingController _searchController;
  String _currentDisplayTicker = '';
  String _lastSuccessfulTicker = '';

  final WalletApiService _apiService = WalletApiService();

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
  void initState() {
    super.initState();
    _crosshairBehavior = CrosshairBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      lineType: CrosshairLineType.vertical,
      lineDashArray: const <double>[5, 5],
    );
    _searchController = TextEditingController(text: widget.ticker);
    _currentDisplayTicker = widget.ticker;
    _lastSuccessfulTicker = widget.ticker; // Initialize last successful ticker
    _fetchStockData();
  }

  @override
  void didUpdateWidget(covariant StockChartAndDetailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ticker != oldWidget.ticker) {
      // Don't set state here, let _fetchStockData handle it atomically.
      _fetchStockData(ticker: widget.ticker);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchStockData({String? ticker}) async {
    final bool isInitialLoad = _stockDetail == null;
    final tickerToFetch = ticker ?? _currentDisplayTicker;

    if (tickerToFetch.isEmpty) {
      return;
    }

    if (isInitialLoad) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final stockDetailData = await _apiService.fetchStockDetail(tickerToFetch);

      if (stockDetailData.isEmpty || stockDetailData.containsKey('error') || stockDetailData['name'] == null) {
        throw Exception('Stock not found or invalid data');
      }
      
      final ohlcvData = await _apiService.fetchOhlcvData(tickerToFetch, _selectedTimeframe);

      final List<dynamic> chartRawData = ohlcvData['data'];

      // Also treat empty chart data as a failure case that should show a popup.
      if (chartRawData.isEmpty) {
        throw Exception('No chart data available');
      }

      final chartData = chartRawData.map((item) => _ChartData(
        DateTime.parse(item['date']),
        item['open'],
        item['high'],
        item['low'],
        item['close'],
        item['volume'],
      )).toList();

      List<_ChartData> smaData = [];
      if (chartData.length >= 5) {
        for (int i = 4; i < chartData.length; i++) {
          double sum = 0;
          for (int j = 0; j < 5; j++) {
            sum += chartData[i - j].close;
          }
          double sma = sum / 5;
          smaData.add(_ChartData(chartData[i].x, 0, 0, 0, 0, 0, sma));
        }
      }

      // Atomic state update on success
      if (mounted) {
        setState(() {
          _currentDisplayTicker = tickerToFetch;
          _searchController.text = tickerToFetch;
          _lastSuccessfulTicker = tickerToFetch;
          _stockDetail = stockDetailData;
          _chartData = chartData;
          _smaData = smaData;
          _error = null; // Explicitly clear any previous errors
        });
      }
    } catch (e) {
      if (mounted) {
        _showNoDataDialog();
        // On failure, revert the search box text to the last successful ticker.
        _searchController.text = _lastSuccessfulTicker;
      }
    } finally {
      if (mounted && isInitialLoad) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  DateFormat _getDateFormat() {
    switch (_selectedTimeframe) {
      case 'M':
        return DateFormat('HH:mm');
      case 'D':
        return DateFormat('yy/MM/dd');
      case 'Y':
        return DateFormat('yyyy');
      default:
        return DateFormat('yy/MM/dd');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;

    // Show loading spinner ONLY if there's no data to display yet (initial load).
    if (_isLoading && _stockDetail == null) {
      body = const Center(child: CircularProgressIndicator());
    }
    // Show error message ONLY if there is no chart data to display.
    else if (_error != null && _chartData.isEmpty) {
      body = Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    // Show initial message if no detail is available after loading.
    else if (_stockDetail == null) {
      body = Center(
        child: Text(
          '종목 정보를 불러올 수 없습니다.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      );
    }
    // Otherwise, always build the main content. This prevents the screen from
    // being replaced by a spinner during a refresh or a failed search.
    else {
      final price = _stockDetail!['price'] ?? 0;
      final diff = _stockDetail!['diff'] ?? 0;
      final rate = _stockDetail!['rate'] ?? 0;
      final volume = _stockDetail!['volume'] ?? 'N/A';
      final open = _stockDetail!['open'] ?? 0;
      final high = _stockDetail!['high'] ?? 0;
      final low = _stockDetail!['low'] ?? 0;

      final isKrw = RegExp(r'^\d{6}$').hasMatch(_currentDisplayTicker);
      final priceColor = diff > 0 ? Colors.red : (diff < 0 ? Colors.blue : Colors.grey);

      body = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Search Bar
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stockDetail!['name'] ?? 'N/A',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _currentDisplayTicker, // Display the current ticker
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Padding( // Added Padding
                    padding: const EdgeInsets.only(right: 16.0), // Added right padding
                    child: SizedBox(
                      width: 150, // Adjust width as needed
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '티커 입력',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              final tickerToSearch = _searchController.text.toUpperCase();
                              // Only search if the ticker is different from the current one.
                              if (tickerToSearch.isNotEmpty && tickerToSearch != _currentDisplayTicker) {
                                _fetchStockData(ticker: tickerToSearch);
                              }
                            },
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        onSubmitted: (value) {
                          final tickerToSearch = value.toUpperCase();
                          if (tickerToSearch.isNotEmpty && tickerToSearch != _currentDisplayTicker) {
                            _fetchStockData(ticker: tickerToSearch);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start, // Align items to the start (top)
                children: [
                  // Left Section: Price Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                      ],
                    ),
                  ),

                  // Right Section: Open, High, Low, Volume Info
                  Padding( // Added Padding
                    padding: const EdgeInsets.only(right: 16.0), // Added right padding
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, // Changed from CrossAxisAlignment.end to CrossAxisAlignment.start
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildDetailItem('시가', isKrw ? NumberFormat('#,###').format(open) : formatPrice(open)),
                            const SizedBox(width: 16),
                            _buildDetailItem('고가', isKrw ? NumberFormat('#,###').format(high) : formatPrice(high)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildDetailItem('저가', isKrw ? NumberFormat('#,###').format(low) : formatPrice(low)),
                            const SizedBox(width: 16),
                            _buildDetailItem('거래량', NumberFormat.compact().format(volume)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Timeframe ToggleButtons
              Center(
                child: ToggleButtons(
                  isSelected: _isSelected,
                  onPressed: (int index) {
                    setState(() {
                      for (int i = 0; i < _isSelected.length; i++) {
                        _isSelected[i] = i == index;
                      }
                      _selectedTimeframe = ['M', 'D', 'Y'][index]; // Changed 'W' back to 'H'
                      _fetchStockData();
                    });
                  },
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  selectedColor: theme.colorScheme.onPrimary,
                  fillColor: theme.colorScheme.primary,
                  borderColor: theme.colorScheme.outline,
                  selectedBorderColor: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 36.0),
                  children: <Widget>[
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text('1분')),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text('1일')),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text('1년')),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Candlestick Chart
              SizedBox(
                height: 250, // Reduced height
                child: _chartData.isEmpty
                    ? Center(child: Text('차트 데이터가 없습니다.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))))
                    : SfCartesianChart(
                        crosshairBehavior: _crosshairBehavior,
                        primaryXAxis: DateTimeAxis(
                          isVisible: true, // Show X axis for the main chart
                          dateFormat: _getDateFormat(),
                          majorGridLines: const MajorGridLines(width: 0),
                          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 10), // Add labelStyle
                        ),
                        primaryYAxis: NumericAxis(
                          opposedPosition: true,
                          numberFormat: isKrw ? NumberFormat.compact() : NumberFormat.compactSimpleCurrency(),
                          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 10),
                        ),
                        series: <CartesianSeries>[
                          CandleSeries<_ChartData, DateTime>(
                            dataSource: _chartData,
                            xValueMapper: (_ChartData data, _) => data.x,
                            lowValueMapper: (_ChartData data, _) => data.low,
                            highValueMapper: (_ChartData data, _) => data.high,
                            openValueMapper: (_ChartData data, _) => data.open,
                            closeValueMapper: (_ChartData data, _) => data.close,
                            bullColor: Colors.red,
                            bearColor: Colors.blue,
                            name: widget.ticker,
                          ),
                          LineSeries<_ChartData, DateTime>(
                            dataSource: _smaData,
                            xValueMapper: (_ChartData data, _) => data.x,
                            yValueMapper: (_ChartData data, _) => data.sma5,
                            color: Colors.orange,
                            width: 1,
                            name: 'SMA 5',
                          ),
                        ],
                      ),
              ),
              // Volume Chart
              SizedBox(
                height: 80, // Reduced height
                child: _chartData.isEmpty
                    ? const SizedBox.shrink()
                    : SfCartesianChart(
                        primaryXAxis: DateTimeAxis(
                          dateFormat: _getDateFormat(),
                          majorGridLines: const MajorGridLines(width: 0),
                          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 10),
                        ),
                        primaryYAxis: NumericAxis(
                          isVisible: true, // Show Y axis for volume chart
                          numberFormat: NumberFormat.compact(),
                          axisLabelFormatter: (AxisLabelRenderDetails details) {
                            final value = details.value;
                            return ChartAxisLabel('${NumberFormat.compact().format(value)}주',
                                TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 10));
                          },
                          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 10),
                        ),
                        series: <CartesianSeries>[
                          ColumnSeries<_ChartData, DateTime>(
                            dataSource: _chartData,
                            xValueMapper: (_ChartData data, _) => data.x,
                            yValueMapper: (_ChartData data, _) => data.volume,
                            name: 'Volume',
                            color: Colors.grey.withOpacity(0.5),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return body;
  }

  Widget _buildDetailItem(String title, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  void _showNoDataDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('알림'),
          content: const Text('데이터가 없습니다.'),
          actions: <Widget>[
            TextButton(
              child: const Text('확인'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}