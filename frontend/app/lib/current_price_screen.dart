import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';

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
  List<ChartData> _chartData = [];
  List<dynamic> _rankingData = [];
  bool _isLoading = false;
  String? _error;
  String _selectedInterval = '1D';
  final List<bool> _isSelected = [false, false, true];

  final WalletApiService _apiService = WalletApiService();

  @override
  void initState() {
    super.initState();
    _fetchRankingData();
  }

  String formatPrice(dynamic price) {
    print('formatPrice: Original price: $price (Type: ${price.runtimeType})');
    if (price == null) {
      print('formatPrice: Price is null, returning N/A');
      return 'N/A';
    }
    // Convert to double to ensure numeric operations
    double value = price.toDouble();
    print('formatPrice: Converted to double: $value');

    // Use NumberFormat to remove unnecessary trailing zeros
    // The pattern '#.####' means show up to 4 decimal places, but remove trailing zeros.
    // If you need more decimal places, adjust the number of #.
    final formatter = NumberFormat('#.####');
    String formatted = formatter.format(value);
    print('formatPrice: Formatted string: $formatted');
    return formatted;
  }

  Future<void> _fetchRankingData() async {
    print('_fetchRankingData: Starting data fetch...');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final rankingData = await _apiService.fetchRankingData();
      print('_fetchRankingData: Data fetched successfully. Count: ${rankingData.length}');
      setState(() {
        _rankingData = rankingData;
      });
    } catch (e) {
      print('_fetchRankingData: Error fetching data: ${e.toString()}');
      setState(() {
        _error = '순위 데이터를 불러오는 데 실패했습니다: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
        print('_fetchRankingData: Loading finished. _isLoading: $_isLoading');
      });
    }
  }

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
      final responseData = await _apiService.fetchOhlcvData(ticker, _selectedInterval);
      final List<dynamic> chartRawData = responseData['data'];

      final List<ChartData> processedData = chartRawData.map((item) {
        return ChartData(
          DateTime.parse(item['date']),
          item['open'].toDouble(),
          item['high'].toDouble(),
          item['low'].toDouble(),
          item['close'].toDouble(),
        );
      }).toList();

      setState(() {
        _chartData = processedData;
      });
    } catch (e) {
      setState(() {
        _error = '차트 데이터를 불러오는 데 실패했습니다: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              child: _isLoading && _chartData.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : _chartData.isNotEmpty
                          ? SfCartesianChart(
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
                            )
                          : const Center(child: Text('종목을 검색해주세요.')),
            ),
            const SizedBox(height: 20),
            const Text('수익률 순위', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Expanded(
              child: _isLoading && _rankingData.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _rankingData.isEmpty
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : _rankingData.isEmpty
                          ? const Center(child: Text('순위 데이터가 없습니다.'))
                          : SingleChildScrollView(
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('순위')),
                                  DataColumn(label: Text('종목명')),
                                  DataColumn(label: Text('현재가')),
                                  DataColumn(label: Text('등락률')),
                                ],
                                rows: _rankingData.asMap().entries.map((entry) {
                                  int index = entry.key;
                                  var stock = entry.value;
                                  return DataRow(
                                    cells: [
                                      DataCell(Text((index + 1).toString())),
                                      DataCell(Text(stock['name'] ?? 'N/A')),
                                      DataCell(Text(formatPrice(stock['price']) ?? 'N/A')),
                                      DataCell(Text('${stock['rate']?.toString() ?? 'N/A'}%')),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
