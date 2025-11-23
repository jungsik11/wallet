import 'package:flutter/material.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';
import 'package:interactive_chart/interactive_chart.dart';
import 'dart:math';

// Adjusted _ChartData to be compatible with interactive_chart's CandleData
class _ChartData extends CandleData {
  _ChartData({
    required DateTime timestamp,
    required double open,
    required double high,
    required double low,
    required double close,
    required double volume,
    List<double>? trends, // Trends property for overlays like SMA
  }) : super(
          timestamp: timestamp.millisecondsSinceEpoch, // Convert DateTime to int millisecondsSinceEpoch
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
          trends: trends, // Pass trends to super constructor
        );
}

// THE MISSING WIDGET CLASS - RE-ADDED
class StockChartAndDetailsView extends StatefulWidget {
  final String ticker;

  const StockChartAndDetailsView({Key? key, required this.ticker}) : super(key: key);

  @override
  _StockChartAndDetailsViewState createState() => _StockChartAndDetailsViewState();
}


class _StockChartAndDetailsViewState extends State<StockChartAndDetailsView> {
  Map<String, dynamic>? _stockDetail;
  List<_ChartData> _chartData = [];
  bool _isLoading = false;
  String? _error;
  String _selectedTimeframe = 'T';
  List<bool> _isSelected = [true, false, false, false, false]; // T, D, W, M, Y
  
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
    _searchController = TextEditingController(text: widget.ticker);
    _currentDisplayTicker = widget.ticker;
    _lastSuccessfulTicker = widget.ticker;
    _fetchStockData();
  }

  @override
  void didUpdateWidget(covariant StockChartAndDetailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ticker != oldWidget.ticker) {
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

    setState(() {
      _isLoading = true;
      _stockDetail = null; // Clear previous stock details
      _chartData = [];      // Clear previous chart data
      _error = null;        // Clear previous error
    });

    try {
      final stockDetailData = await _apiService.fetchStockDetail(tickerToFetch);

      if (stockDetailData.isEmpty || stockDetailData.containsKey('error') || stockDetailData['name'] == null) {
        if (mounted) {
          setState(() {
            _error = '종목을 찾을 수 없거나 데이터가 유효하지 않습니다.';
          });
          _showErrorSnackbar(_error!);
        }
        return; // Return early if stock detail is invalid
      }
      
      final ohlcvData = await _apiService.fetchOhlcvData(tickerToFetch, _selectedTimeframe);

      final List<dynamic> chartRawData = ohlcvData['data'];

      if (chartRawData.isEmpty) {
        if (mounted) {
          setState(() {
            _error = '차트 데이터를 불러올 수 없습니다.';
          });
          _showErrorSnackbar(_error!);
        }
        return; // Return early if no chart data
      }

      final List<_ChartData> fetchedChartData = chartRawData.map((item) {
        return _ChartData(
          timestamp: DateTime.parse(item['date']),
          open: item['open']?.toDouble() ?? 0.0,
          high: item['high']?.toDouble() ?? 0.0,
          low: item['low']?.toDouble() ?? 0.0,
          close: item['close']?.toDouble() ?? 0.0,
          volume: item['volume']?.toDouble() ?? 0.0,
        );
      }).toList();

      // InteractiveChart expects candles in chronological order (oldest first)
      // The API now returns oldest first, so no need to reverse.
      final List<_ChartData> chronologicalChartData = fetchedChartData;

      // Calculate SMA (Simple Moving Average) and assign to CandleData.trends
      final ma5 = CandleData.computeMA(chronologicalChartData, 5);

      for (int i = 0; i < chronologicalChartData.length; i++) {
        // Assign SMA as the first trend line (index 0)
        // Ensure trends list is initialized if null
        chronologicalChartData[i].trends = [ma5[i]];
      }

      if (mounted) {
        setState(() {
          _currentDisplayTicker = tickerToFetch;
          _searchController.text = tickerToFetch;
          _lastSuccessfulTicker = tickerToFetch;
          _stockDetail = stockDetailData;
          _chartData = chronologicalChartData;
          _error = null; // Clear error if data loaded successfully
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stockDetail = null;
          _chartData = [];
          _error = '데이터를 불러오는 중 오류가 발생했습니다: $e';
        });
        _showErrorSnackbar(_error!);
        _searchController.text = _lastSuccessfulTicker; // Revert to last successful ticker on error
      }
    } finally {
      if (mounted) { // Always set _isLoading to false
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getBottomLabelText(int index, int totalVisibleCandles) {
    if (index < 0 || index >= _chartData.length) {
      return '';
    }

    // Determine how many labels to display. Let's aim for a few, like 3 to 5 labels plus the first and last.
    int desiredLabels = 5; // A reasonable number of labels to aim for
    int actualLabels = min(desiredLabels, totalVisibleCandles);

    // Calculate an interval. Ensure it's at least 1 to avoid division by zero or errors.
    int interval = (totalVisibleCandles <= desiredLabels) ? 1 : (totalVisibleCandles / (desiredLabels - 1)).ceil();
    if (interval == 0) interval = 1;


    // Always display the first and last label. Display intermediate labels at calculated intervals.
    if (index == 0 || index == _chartData.length - 1 || (index % interval == 0 && totalVisibleCandles > desiredLabels)) {
      final DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(_chartData[index].timestamp);
      switch (_selectedTimeframe) {
        case 'T': return DateFormat('HH:mm').format(timestamp);
        case 'D': case 'W': return DateFormat('MM/dd').format(timestamp);
        case 'M': return DateFormat('yy/MM').format(timestamp);
        case 'Y': return DateFormat('yyyy').format(timestamp);
        default: return DateFormat('MM/dd').format(timestamp);
      }
    }

    return ''; // For other indices, return empty string
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;

    if (_isLoading && _stockDetail == null) {
      body = const Center(child: CircularProgressIndicator());
    }
    else if (_error != null) { // Prioritize displaying specific error messages
      body = Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    else if (_stockDetail == null) { // This case should ideally be covered by _error now, but kept for robustness
      body = Center(
        child: Text(
          '종목 정보를 불러올 수 없습니다.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      );
    }
    else {
      final price = _stockDetail?['price'] ?? 0.0; // Use 0.0 for numeric defaults
      final diff = _stockDetail?['diff'] ?? 0.0;
      final rate = _stockDetail?['rate'] ?? 0.0;
      final volume = _stockDetail?['volume'] ?? 0; // Use 0 for numeric defaults
      final open = _stockDetail?['open'] ?? 0.0;
      final high = _stockDetail?['high'] ?? 0.0;
      final low = _stockDetail?['low'] ?? 0.0;

      final isKrw = RegExp(r'^\d{6}$').hasMatch(_currentDisplayTicker);
      final priceColor = diff > 0 ? Colors.green : (diff < 0 ? Colors.red : Colors.grey);

      body = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stockDetail?['name'] ?? 'N/A', // Null-safe access
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _currentDisplayTicker,
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '티커 입력',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              final tickerToSearch = _searchController.text.toUpperCase();
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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

              Center(
                child: ToggleButtons(
                  isSelected: _isSelected,
                  onPressed: (int index) {
                    setState(() {
                      for (int i = 0; i < _isSelected.length; i++) {
                        _isSelected[i] = i == index;
                      }
                      _selectedTimeframe = ['T', 'D', 'W', 'M', 'Y'][index];
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
                  children: const <Widget>[
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1분')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1일')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1주')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1달')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1년')),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                height: 330,
                child: _chartData.isEmpty
                    ? Center(child: Text('차트 데이터가 없습니다.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))))
                    : InteractiveChart(
                        candles: _chartData,
                        style: ChartStyle(
                          priceGainColor: Colors.green,
                          priceLossColor: Colors.red,
                          volumeColor: Colors.grey.withOpacity(0.5),
                          volumeHeightFactor: 0.2,
                          overlayBackgroundColor: Colors.black.withOpacity(0.5),
                          timeLabelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 10),
                          priceLabelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 10),
                          trendLineStyles: [
                              Paint()
                                ..strokeWidth = 1.5
                                ..strokeCap = StrokeCap.round
                                ..color = Colors.orange,
                          ]
                        ),
                        timeLabel: _getBottomLabelText,
                        // overlays parameter is not used as trends are assigned to CandleData
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