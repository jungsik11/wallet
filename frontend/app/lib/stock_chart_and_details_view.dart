import 'package:flutter/material.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:app/responsive_text.dart'; // Assuming this is needed for chart labels

class StockChartAndDetailsView extends StatefulWidget {
  final String ticker;

  const StockChartAndDetailsView({Key? key, required this.ticker}) : super(key: key);

  @override
  _StockChartAndDetailsViewState createState() => _StockChartAndDetailsViewState();
}

class _ChartData {
  _ChartData(this.x, this.open, this.high, this.low, this.close);
  final DateTime x;
  final num open;
  final num high;
  final num low;
  final num close;

  factory _ChartData.fromJson(Map<String, dynamic> json) {
    return _ChartData(
      DateTime.parse(json['date']),
      json['open'],
      json['high'],
      json['low'],
      json['close'],
    );
  }
}

class _StockChartAndDetailsViewState extends State<StockChartAndDetailsView> {
  Map<String, dynamic>? _stockDetail;
  List<_ChartData> _chartData = [];
  bool _isLoading = false;
  String? _error;
  String _selectedTimeframe = 'D';
  String _market = '';
  List<bool> _isSelected = [false, false, true]; // M, H, D

  final WalletApiService _apiService = WalletApiService();

  // Add TextEditingController for search
  late TextEditingController _searchController;
  late String _currentTicker; // To hold the ticker being displayed/searched

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
    _currentTicker = widget.ticker; // Initialize with the passed ticker
    _searchController = TextEditingController(text: _currentTicker); // Set initial text
    _fetchStockData();
  }

  @override
  void didUpdateWidget(covariant StockChartAndDetailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ticker != oldWidget.ticker) {
      _currentTicker = widget.ticker; // Update if parent widget changes ticker
      _searchController.text = _currentTicker; // Update search field
      _fetchStockData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose(); // Dispose the controller
    super.dispose();
  }

  Future<void> _fetchStockData() async {
    final tickerToFetch = _currentTicker.isNotEmpty ? _currentTicker : widget.ticker; // Use search input if available

    if (tickerToFetch.isEmpty) {
      setState(() {
        _error = '티커가 제공되지 않았습니다.';
        _stockDetail = null;
        _chartData = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _stockDetail = null;
      _chartData = [];
    });

    try {
      final stockDetailData = await _apiService.fetchStockDetail(tickerToFetch);
      final ohlcvData = await _apiService.fetchOhlcvData(tickerToFetch, _selectedTimeframe);

      final List<dynamic> chartRawData = ohlcvData['data'];

      setState(() {
        _stockDetail = stockDetailData;
        _market = ohlcvData['market'];
        _chartData = chartRawData.map((item) => _ChartData.fromJson(item)).toList();
        if (_chartData.isEmpty) {
          _error = '해당 기간에 대한 차트 데이터가 없습니다.';
        }
      });
    } catch (e) {
      if (e.toString().contains('404')) {
        setState(() {
          _error = '티커를 찾을 수 없습니다. 정확한 티커를 입력해주세요.';
        });
      } else {
        setState(() {
          _error = '데이터를 불러오는 데 실패했습니다: ${e.toString()}';
        });
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  DateFormat _getDateFormat() {
    switch (_selectedTimeframe) {
      case 'M':
        return DateFormat('HH:mm');
      case 'H':
        return DateFormat('MM/dd HH:mm');
      case 'D':
      default:
        return DateFormat('yy/MM/dd');
    }
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

    if (_stockDetail == null) {
      return Center(
        child: Text(
          '종목 정보를 불러올 수 없습니다.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: kToolbarHeight), // Add this line
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: '종목 검색 (예: PLTR)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      setState(() {
                        _currentTicker = _searchController.text.trim();
                      });
                      _fetchStockData();
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  setState(() {
                    _currentTicker = value.trim();
                  });
                  _fetchStockData();
                },
              ),
            ),
            const SizedBox(height: 16), // Spacing after search bar
            Text('종목명: ${_stockDetail!['name'] ?? 'N/A'}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text('현재가: ${formatPrice(_stockDetail!['price'])} ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            
            Text('등락률: ${formatPrice(_stockDetail!['rate'])}%', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text('거래량: ${_stockDetail!['volume'] ?? 'N/A'}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            // Chart Title
            Text(
              '${_stockDetail!['name'] ?? 'N/A'} (${_stockDetail!['ticker'] ?? 'N/A'}) 차트',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            // Timeframe ToggleButtons
            if (_currentTicker.isNotEmpty) // Use _currentTicker instead of widget.ticker
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ToggleButtons(
                  isSelected: _isSelected,
                  onPressed: (int index) {
                    setState(() {
                      for (int i = 0; i < _isSelected.length; i++) {
                        _isSelected[i] = i == index;
                      }
                      _selectedTimeframe = ['M', 'H', 'D'][index];
                      _fetchStockData(); // Re-fetch data with new timeframe
                    });
                  },
                  color: theme.colorScheme.onSurface.withOpacity(0.7), // Unselected text color
                  selectedColor: theme.colorScheme.onPrimary, // Selected text color
                  fillColor: theme.colorScheme.primary, // Selected background color
                  borderColor: theme.colorScheme.outline, // Border color
                  selectedBorderColor: theme.colorScheme.primary, // Selected border color
                  splashColor: theme.colorScheme.primary.withOpacity(0.2), // Splash color
                  highlightColor: theme.colorScheme.primary.withOpacity(0.1), // Highlight color
                  constraints: const BoxConstraints(minHeight: 36.0),
                  children: <Widget>[
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text('1분', style: TextStyle(fontSize: getResponsiveFontSize(context, 14)))),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text('1시간', style: TextStyle(fontSize: getResponsiveFontSize(context, 14)))),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text('1일', style: TextStyle(fontSize: getResponsiveFontSize(context, 14)))),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            // Candlestick Chart
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4, // Responsive height
              child: _chartData.isEmpty
                  ? Center(
                      child: Text(
                        _error != null ? _error! : '차트 데이터가 없습니다.',
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                      ),
                    )
                  : SfCartesianChart(
                      backgroundColor: Colors.transparent,
                      plotAreaBackgroundColor: Colors.transparent,
                      margin: EdgeInsets.zero,
                      plotAreaBorderWidth: 0,
                      trackballBehavior: TrackballBehavior(
                        enable: true,
                        activationMode: ActivationMode.singleTap,
                        lineType: TrackballLineType.vertical,
                        lineDashArray: const <double>[5, 5],
                        tooltipSettings: InteractiveTooltip(
                          enable: true,
                          color: theme.colorScheme.surface, // Use theme surface color
                          borderColor: theme.colorScheme.outline, // Use theme outline color
                          borderWidth: 1,
                          format: 'point.x\nOpen: point.open\nHigh: point.high\nLow: point.low\nClose: point.close\nVolume: point.volume', // Custom tooltip format
                        ),
                      ),
                      primaryXAxis: DateTimeAxis(
                        dateFormat: _getDateFormat(),
                        majorGridLines: const MajorGridLines(width: 0),
                        labelStyle: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12), // Increased font size
                        axisLine: AxisLine(width: 0, color: theme.colorScheme.outline), // Axis line color
                      ),
                      primaryYAxis: NumericAxis(
                        opposedPosition: true,
                        rangePadding: ChartRangePadding.round,
                        axisLabelFormatter: (AxisLabelRenderDetails details) {
                          final value = details.value;
                          String formattedText;
                          if (_market == 'KRX') {
                            formattedText = '${NumberFormat.compact().format(value / 10000)} 만원';
                          } else {
                            formattedText = NumberFormat.compactSimpleCurrency(locale: 'en_US').format(value);
                          }
                          return ChartAxisLabel(formattedText, TextStyle(color: theme.colorScheme.onSurface, fontSize: 12)); // Increased font size
                        },
                        axisLine: AxisLine(width: 0, color: theme.colorScheme.outline), // Axis line color
                        majorGridLines: MajorGridLines(width: 0.5, color: theme.colorScheme.outline.withOpacity(0.3), dashArray: const <double>[2, 2]), // More subtle gridlines
                      ),
                      series: <CandleSeries<_ChartData, DateTime>>[
                        CandleSeries<_ChartData, DateTime>(
                          dataSource: _chartData,
                          xValueMapper: (_ChartData data, _) => data.x,
                          lowValueMapper: (_ChartData data, _) => data.low,
                          highValueMapper: (_ChartData data, _) => data.high,
                          openValueMapper: (_ChartData data, _) => data.open,
                          closeValueMapper: (_ChartData data, _) => data.close,
                          enableSolidCandles: true,
                          bullColor: Colors.green.shade700, // Darker green for bullish
                          bearColor: Colors.red.shade700, // Darker red for bearish
                        )
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

