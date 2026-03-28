import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:app/services/wallet_api_service.dart';

class StockTradingScreen extends StatefulWidget {
  final String ticker;

  const StockTradingScreen({Key? key, required this.ticker}) : super(key: key);

  @override
  _StockTradingScreenState createState() => _StockTradingScreenState();
}

class _StockTradingScreenState extends State<StockTradingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final WalletApiService _apiService = WalletApiService();
  Map<String, dynamic>? _orderbook;
  Map<String, dynamic>? _stockDetail;
  List<_ChartData> _chartData = [];
  String _selectedTimeframe = 'D';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Fetch all data in parallel
      final responses = await Future.wait([
        _apiService.fetchOrderbook(widget.ticker),
        _apiService.fetchStockDetail(widget.ticker),
        _apiService.fetchOhlcvData(widget.ticker, _selectedTimeframe),
      ]);

      final orderbookData = responses[0] as Map<String, dynamic>;
      final stockDetailData = responses[1] as Map<String, dynamic>;
      final ohlcvData = responses[2] as Map<String, dynamic>;
      
      final List<dynamic> chartRawData = ohlcvData['data'];
      final chartData = chartRawData.map((item) => _ChartData.fromJson(item)).toList();

      setState(() {
        _orderbook = orderbookData;
        _stockDetail = stockDetailData;
        _chartData = chartData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
    final formatter = NumberFormat('#,###.##');
    return formatter.format(value);
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
    final screenHeight = MediaQuery.of(context).size.height;
    final chartHeight = screenHeight * 0.6; // 60% of screen height

    return Column(
      children: [
        _buildStockInfo(),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '호가'),
            Tab(text: '차트'),
          ],
        ),
        SizedBox(
          height: chartHeight,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOrderBook(),
              _buildChart(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStockInfo() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Center(child: Text('Error: $_error')),
      );
    }

    if (_stockDetail == null) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: Text('No stock detail data.')),
      );
    }

    final rate = _stockDetail!['rate'] as num? ?? 0;
    final color = rate >= 0 ? Colors.red : Colors.blue;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_stockDetail!['name'] ?? 'N/A'} | ${widget.ticker}'),
          Row(
            children: [
              Text(
                formatPrice(_stockDetail!['price']),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                '${rate.toStringAsFixed(2)}%',
                style: TextStyle(color: color),
              ),
            ],
          ),
          Text('Volume: ${formatPrice(_stockDetail!['volume'])}'),
        ],
      ),
    );
  }

  Widget _buildOrderBook() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }

    if (_orderbook == null) {
      return const Center(child: Text('No order book data.'));
    }

    final List<dynamic> asks = _orderbook!['asks'] ?? [];
    final List<dynamic> bids = _orderbook!['bids'] ?? [];

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: _buildOrderBookSide(
                  title: '매도',
                  orders: asks.cast<Map<String, dynamic>>(),
                  isBid: false,
                ),
              ),
              Expanded(
                child: _buildOrderBookSide(
                  title: '매수',
                  orders: bids.cast<Map<String, dynamic>>(),
                  isBid: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: _buildTradeInfo(),
        ),
      ],
    );
  }

  Widget _buildOrderBookSide(
      {required String title,
      required List<Map<String, dynamic>> orders,
      required bool isBid}) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Text(title),
          DataTable(
            columns: const [
              DataColumn(label: Text('가격')),
              DataColumn(label: Text('수량')),
            ],
            rows: orders
                .map(
                  (order) => DataRow(
                    cells: [
                      DataCell(
                        Text(
                          order['price'].toString(),
                          style: TextStyle(color: isBid ? Colors.red : Colors.blue),
                        ),
                      ),
                      DataCell(Text(order['size'].toString())),
                    ],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeInfo() {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('체결강도: 190.66%'),
          SizedBox(height: 16),
          Text('52주최고: 1.1850'),
          Text('52주최저: 0.4203'),
          Text('호가단위: 0.0100'),
          Text('시: 1.1400'),
          Text('고: 1.1800'),
          Text('저: 1.0400'),
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_chartData.isEmpty) {
      return const Center(child: Text('No chart data available.'));
    }

    return Column(
      children: [
        _buildChartToolbar(),
        Expanded(
          child: SfCartesianChart(
            primaryXAxis: DateTimeAxis(
              dateFormat: _getDateFormat(),
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
                bullColor: Colors.green,
                bearColor: Colors.red,
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChartToolbar() {
    final timeframes = ['D', 'H', 'M'];
    final labels = ['1일', '1시간', '1분'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(timeframes.length, (index) {
          return _buildToolbarButton(
            labels[index],
            isSelected: _selectedTimeframe == timeframes[index],
            onPressed: () {
              setState(() {
                _selectedTimeframe = timeframes[index];
              });
              _fetchData();
            },
          );
        }),
      ),
    );
  }

  Widget _buildToolbarButton(String text, {required bool isSelected, required VoidCallback onPressed}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
        ),
      ),
    );
  }
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
      json['open'] as num,
      json['high'] as num,
      json['low'] as num,
      json['close'] as num,
    );
  }
}