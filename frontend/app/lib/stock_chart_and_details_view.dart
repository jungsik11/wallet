import 'package:flutter/material.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:math';

// Data class for Syncfusion chart
class _ChartData {
  _ChartData(this.timestamp, this.open, this.high, this.low, this.close, this.volume);

  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
}

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
  
  late ZoomPanBehavior _zoomPanBehavior;
  late TrackballBehavior _trackballBehavior;


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

    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      enableDoubleTapZooming: true,
    );
    _trackballBehavior = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipSettings: const InteractiveTooltip(
        enable: true,
      ),
    );

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
    final tickerToFetch = ticker ?? _currentDisplayTicker;

    if (tickerToFetch.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _stockDetail = null;
      _chartData = [];
      _error = null;
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
        return;
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
        return;
      }

      final List<_ChartData> fetchedChartData = chartRawData.map((item) {
        return _ChartData(
          DateTime.parse(item['date']),
          item['open']?.toDouble() ?? 0.0,
          item['high']?.toDouble() ?? 0.0,
          item['low']?.toDouble() ?? 0.0,
          item['close']?.toDouble() ?? 0.0,
          item['volume']?.toDouble() ?? 0.0,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _currentDisplayTicker = tickerToFetch;
          _searchController.text = tickerToFetch;
          _lastSuccessfulTicker = tickerToFetch;
          _stockDetail = stockDetailData;
          _chartData = fetchedChartData;
          _error = null;
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
        _searchController.text = _lastSuccessfulTicker;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;

    if (_isLoading && _stockDetail == null) {
      body = const Center(child: CircularProgressIndicator());
    }
    else if (_error != null) {
      body = Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    else if (_stockDetail == null) {
      body = Center(
        child: Text(
          '종목 정보를 불러올 수 없습니다.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      );
    }
    else {
      final price = _stockDetail?['price'] ?? 0.0;
      final diff = _stockDetail?['diff'] ?? 0.0;
      final rate = _stockDetail?['rate'] ?? 0.0;
      final volume = _stockDetail?['volume'] ?? 0;
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
                          _stockDetail?['name'] ?? 'N/A',
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
                      _selectedTimeframe = ['T', 'H', 'D', 'M', 'Y'][index];
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
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1시간')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1일')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1달')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1년')),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                height: 400,
                child: _chartData.isEmpty
                    ? Center(child: Text('차트 데이터가 없습니다.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))))
                    : Column(
                        children: [
                          Expanded(
                            flex: 3, // Price chart takes 3/4 of the space
                            child: SfCartesianChart(
                              primaryXAxis: DateTimeAxis(
                                isVisible: false, // Hide X-axis on the price chart
                                name: 'xAxis', // Name for linking
                              ),
                              primaryYAxis: NumericAxis(
                                numberFormat: NumberFormat.compact(),
                                majorGridLines: const MajorGridLines(width: 0.5),
                                opposedPosition: true,
                                labelStyle: TextStyle(color: theme.colorScheme.onSurface),
                              ),
                              series: <CartesianSeries>[
                                CandleSeries<_ChartData, DateTime>(
                                  dataSource: _chartData,
                                  xValueMapper: (_ChartData data, _) => data.timestamp,
                                  lowValueMapper: (_ChartData data, _) => data.low,
                                  highValueMapper: (_ChartData data, _) => data.high,
                                  openValueMapper: (_ChartData data, _) => data.open,
                                  closeValueMapper: (_ChartData data, _) => data.close,
                                  enableSolidCandles: true,
                                  bullColor: Colors.green,
                                  bearColor: Colors.red,
                                ),
                              ],
                              zoomPanBehavior: _zoomPanBehavior,
                              trackballBehavior: _trackballBehavior,
                            ),
                          ),
                          Expanded(
                            flex: 1, // Volume chart takes 1/4 of the space
                            child: SfCartesianChart(
                              primaryXAxis: DateTimeAxis(
                                name: 'xAxis', // Same name for linking
                                dateFormat: _getDateFormatForTimeframe(),
                                intervalType: _getIntervalTypeForTimeframe(),
                                majorGridLines: const MajorGridLines(width: 0),
                                labelStyle: TextStyle(color: theme.colorScheme.onSurface),
                                desiredIntervals: 5, // Limit to 5 labels
                              ),
                              primaryYAxis: NumericAxis(
                                numberFormat: NumberFormat.compact(),
                                majorGridLines: const MajorGridLines(width: 0),
                                labelStyle: TextStyle(color: theme.colorScheme.onSurface),
                                opposedPosition: true, // Move Y-axis to the right
                              ),
                              series: <CartesianSeries>[
                                ColumnSeries<_ChartData, DateTime>(
                                  dataSource: _chartData,
                                  xValueMapper: (_ChartData data, _) => data.timestamp,
                                  yValueMapper: (_ChartData data, _) => data.volume,
                                  color: Colors.grey.withOpacity(0.5),
                                ),
                              ],
                              zoomPanBehavior: _zoomPanBehavior,
                              trackballBehavior: _trackballBehavior,
                            ),
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
  
  DateFormat _getDateFormatForTimeframe() {
    DateFormat format;
    switch (_selectedTimeframe) {
      case 'T':
        format = DateFormat.Hm(); // HH:mm
        break;
      case 'H': // New: 1 Hour
        format = DateFormat.Hm(); // HH:mm
        break;
      case 'D': // New: 1 Day
        format = DateFormat.Md(); // MM/dd
        break;
      case 'M':
        format = DateFormat('yy/MM'); // yy/MM
        break;
      case 'Y':
        format = DateFormat.y(); // yyyy
        break;
      default:
        format = DateFormat.Md();
        break;
    }
    return format;
  }

  DateTimeIntervalType _getIntervalTypeForTimeframe() {
    DateTimeIntervalType type;
    switch (_selectedTimeframe) {
      case 'T':
        type = DateTimeIntervalType.minutes;
        break;
      case 'H': // New: 1 Hour
        type = DateTimeIntervalType.hours;
        break;
      case 'D': // New: 1 Day
        type = DateTimeIntervalType.days;
        break;
      case 'M':
        type = DateTimeIntervalType.months;
        break;
      case 'Y':
        type = DateTimeIntervalType.years;
        break;
      default:
        type = DateTimeIntervalType.auto;
        break;
    }
    return type;
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

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
