import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:syncfusion_flutter_charts/charts.dart';

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
          );
        }).toList();

        setState(() {
          _chartData = processedData;
        });
      } else {
        throw Exception('Failed to load chart data');
      }
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
}
