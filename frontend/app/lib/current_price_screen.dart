import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:syncfusion_flutter_charts/charts.dart';
<<<<<<< Updated upstream
import 'package:intl/intl.dart';
=======
>>>>>>> Stashed changes

class ChartData {
  ChartData(this.x, this.open, this.high, this.low, this.close);
  final DateTime x;
  final double open;
  final double high;
  final double low;
  final double close;
}

class CurrentPriceScreen extends StatefulWidget {
  const CurrentPriceScreen({Key? key}) : super(key: key);

  @override
  _CurrentPriceScreenState createState() => _CurrentPriceScreenState();
}

class _CurrentPriceScreenState extends State<CurrentPriceScreen> {
  final TextEditingController _tickerController = TextEditingController();
<<<<<<< Updated upstream
  bool _isLoading = false;
  String? _error;
  List<ChartData> _chartData = [];
  double? _currentPrice;
  String _searchedTicker = '';
  String _selectedTimeframe = '1d'; // Default timeframe
  final List<String> _timeframes = ['1m', '1h', '1d'];

  Future<void> _fetchChartData(String ticker) async {
    if (ticker.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
      // Only clear chart data if it's a new ticker search
      if (_searchedTicker != ticker.toUpperCase()) {
        _chartData = [];
        _currentPrice = null;
      }
      _searchedTicker = ticker.toUpperCase();
    });

    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:8000/ohlcv/$_searchedTicker?timeframe=$_selectedTimeframe'));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<ChartData> chartData = data.map((item) {
          return ChartData(
            DateTime.parse(item['time']),
            (item['open'] as num).toDouble(),
            (item['high'] as num).toDouble(),
            (item['low'] as num).toDouble(),
            (item['close'] as num).toDouble(),
=======
  List<ChartData> _chartData = [];
  bool _isLoading = false;
  String? _error;
  String _selectedInterval = '1D'; // 1m, 1h, 1D
  final List<bool> _isSelected = [false, false, true];

  Future<void> _fetchChartData() async {
    if (_tickerController.text.isEmpty) {
      return;
    }
    setState(() {
      _isLoading = true;
      _chartData = [];
      _error = null;
    });

    try {
      final ticker = _tickerController.text.toUpperCase();
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/chart/$ticker?interval=$_selectedInterval'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> chartRawData = jsonDecode(utf8.decode(response.bodyBytes));
        final List<ChartData> processedData = chartRawData.map((item) {
          return ChartData(
            DateTime.parse(item['time']),
            item['open'].toDouble(),
            item['high'].toDouble(),
            item['low'].toDouble(),
            item['close'].toDouble(),
>>>>>>> Stashed changes
          );
        }).toList();

        setState(() {
<<<<<<< Updated upstream
          _chartData = chartData;
          if (_chartData.isNotEmpty) {
            _currentPrice = _chartData.last.close;
          }
        });
      } else {
        throw Exception('Failed to load chart data: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _error = '데이터를 불러오는 데 실패했습니다: $e';
=======
          _chartData = processedData;
        });
      } else {
        throw Exception('Failed to load chart data');
      }
    } catch (e) {
      setState(() {
        _error = '차트 데이터를 불러오는 데 실패했습니다: ${e.toString()}';
>>>>>>> Stashed changes
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
<<<<<<< Updated upstream
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _tickerController,
            decoration: InputDecoration(
              labelText: '종목 코드 입력',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _fetchChartData(_tickerController.text),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            onSubmitted: _fetchChartData,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : _chartData.isEmpty
                        ? const Center(child: Text('종목을 검색하여 현재가와 차트를 확인하세요.'))
                        : _buildChartAndPrice(),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double value, String ticker) {
    // Check if the ticker is a 6-digit number (Korean stock)
    final isKoreanStock = RegExp(r'^\d{6}$').hasMatch(ticker);
    if (isKoreanStock) {
      final format = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');
      return format.format(value);
    } else {
      final format = NumberFormat.currency(locale: 'en_US', symbol: '\$');
      return format.format(value);
    }
  }

  Widget _buildChartAndPrice() {
    return Column(
      children: [
        Text(
          _searchedTicker,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _formatCurrency(_currentPrice ?? 0, _searchedTicker),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ToggleButtons(
          isSelected: _timeframes.map((tf) => tf == _selectedTimeframe).toList(),
          onPressed: (int index) {
            setState(() {
              _selectedTimeframe = _timeframes[index];
            });
            if (_searchedTicker.isNotEmpty) {
              _fetchChartData(_searchedTicker);
            }
          },
          borderRadius: BorderRadius.circular(8.0),
          selectedColor: Colors.white,
          fillColor: Colors.blueAccent,
          color: Colors.white70,
          constraints: const BoxConstraints(minHeight: 40, minWidth: 80),
          children: _timeframes.map((tf) => Text(tf.toUpperCase())).toList(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SfCartesianChart(
            primaryXAxis: DateTimeAxis(),
            series: <CartesianSeries>[
              CandleSeries<ChartData, DateTime>(
                dataSource: _chartData,
                xValueMapper: (ChartData data, _) => data.x,
                lowValueMapper: (ChartData data, _) => data.low,
                highValueMapper: (ChartData data, _) => data.high,
                openValueMapper: (ChartData data, _) => data.open,
                closeValueMapper: (ChartData data, _) => data.close,
              )
            ],
          ),
        ),
      ],
    );
  }
=======
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tickerController,
                    decoration: const InputDecoration(
                      labelText: '종목코드 입력',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _fetchChartData,
                  child: const Text('검색'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ToggleButtons(
              isSelected: _isSelected,
              onPressed: (int index) {
                setState(() {
                  for (int i = 0; i < _isSelected.length; i++) {
                    _isSelected[i] = i == index;
                  }
                  _selectedInterval = ['1m', '1h', '1D'][index];
                  _fetchChartData();
                });
              },
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1분')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1시간')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1일')),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : _chartData.isEmpty
                          ? const Center(child: Text('종목을 검색해주세요.'))
                          : SfCartesianChart(
                              primaryXAxis: const DateTimeAxis(),
                              series: <CandleSeries>[
                                CandleSeries<ChartData, DateTime>(
                                  dataSource: _chartData,
                                  xValueMapper: (ChartData data, _) => data.x,
                                  lowValueMapper: (ChartData data, _) => data.low,
                                  highValueMapper: (ChartData data, _) => data.high,
                                  openValueMapper: (ChartData data, _) => data.open,
                                  closeValueMapper: (ChartData data, _) => data.close,
                                ),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }
>>>>>>> Stashed changes
}
