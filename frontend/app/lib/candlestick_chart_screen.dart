import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class CandlestickChartScreen extends StatefulWidget {
  const CandlestickChartScreen({Key? key}) : super(key: key);

  @override
  _CandlestickChartScreenState createState() => _CandlestickChartScreenState();
}

class _CandlestickChartScreenState extends State<CandlestickChartScreen> {
  final TextEditingController _tickerController = TextEditingController();
  List<_ChartData> _chartData = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedTicker = '';
  String _selectedTimeframe = 'D';
  String _market = '';
  List<bool> _isSelected = [false, false, true]; // M, H, D

  @override
  void dispose() {
    _tickerController.dispose();
    super.dispose();
  }

  Future<void> _fetchChartData(String ticker) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedTicker = ticker.toUpperCase();
    });

    try {
      final response = await http.get(Uri.parse('http://localhost:8000/ohlcv?ticker=$_selectedTicker&timeframe=$_selectedTimeframe'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> data = responseData['data'];
        if (mounted) {
          setState(() {
            _market = responseData['market'];
            _chartData = data.map((item) => _ChartData.fromJson(item)).toList();
            if (_chartData.isEmpty) {
              _errorMessage = '해당 기간에 대한 데이터가 없습니다.';
            }
          });
        }
      } else {
        final error = jsonDecode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _errorMessage = '데이터를 불러오는데 실패했습니다: ${error['detail']}';
            _chartData = [];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '오류가 발생했습니다: $e';
          _chartData = [];
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _tickerController,
                    decoration: const InputDecoration(
                      labelText: '티커 입력 (예: 005930)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10.0),
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) _fetchChartData(value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  if (_tickerController.text.isNotEmpty) _fetchChartData(_tickerController.text);
                },
                tooltip: '검색',
              ),
            ],
          ),
          if (_selectedTicker.isNotEmpty)
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
                    _fetchChartData(_selectedTicker);
                  });
                },
                constraints: const BoxConstraints(minHeight: 36.0),
                children: const <Widget>[
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1분')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1시간')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('1일')),
                ],
              ),
            ),
          Flexible(
            flex: 5,
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : _errorMessage != null
                      ? Text(_errorMessage!, textAlign: TextAlign.center)
                      : _chartData.isEmpty
                          ? Text(_selectedTicker.isEmpty ? '티커를 검색하여 캔들차트를 확인하세요.' : '데이터가 없습니다.')
                          : FractionallySizedBox(
                              widthFactor: 0.8,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(10, 15, 10, 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[850],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SfCartesianChart(
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
                                      color: Colors.grey[800],
                                      borderColor: Colors.white30,
                                      borderWidth: 1,
                                    ),
                                  ),
                                  primaryXAxis: DateTimeAxis(
                                    dateFormat: _getDateFormat(),
                                    majorGridLines: const MajorGridLines(width: 0),
                                    labelStyle: const TextStyle(color: Colors.white70, fontSize: 10),
                                    axisLine: const AxisLine(width: 0),
                                  ),
                                  primaryYAxis: NumericAxis(
                                    opposedPosition: true,
                                    rangePadding: ChartRangePadding.round,
                                    axisLabelFormatter: (AxisLabelRenderDetails details) {
                                      final value = details.value;
                                      String formattedText;
                                      if (_market == 'KRX') {
                                        formattedText = '${NumberFormat.compact().format(value / 10000)}만';
                                      } else {
                                        formattedText = NumberFormat.compactSimpleCurrency(locale: 'en_US').format(value);
                                      }
                                      return ChartAxisLabel(formattedText, const TextStyle(color: Colors.white70, fontSize: 10));
                                    },
                                    axisLine: const AxisLine(width: 0),
                                    majorGridLines: const MajorGridLines(width: 0.5, color: Colors.white24, dashArray: <double>[2, 2]),
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
                                      bullColor: Colors.red,
                                      bearColor: Colors.blue,
                                    )
                                  ],
                                ),
                              ),
                            ),
            ),
          ),
          const Spacer(flex: 6),
        ],
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
      json['open'],
      json['high'],
      json['low'],
      json['close'],
    );
  }
}
