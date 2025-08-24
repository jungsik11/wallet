import 'package:flutter/material.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:app/responsive_text.dart'; // Assuming this is needed for chart labels
import 'package:app/stock_trading_screen.dart';

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
            
            StockTradingScreen(ticker: _currentTicker),
          ],
        ),
      ),
    );
  }
}