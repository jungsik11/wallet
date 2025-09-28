import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';
import 'package:app/stock_chart_and_details_view.dart';

class CurrentPriceScreen extends StatefulWidget {
  const CurrentPriceScreen({Key? key}) : super(key: key);

  @override
  _CurrentPriceScreenState createState() => _CurrentPriceScreenState();
}

class _CurrentPriceScreenState extends State<CurrentPriceScreen> {
  double _parseToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    } else if (value is num) {
      return value.toDouble();
    }
    return 0.0;
  }

  List<dynamic> _usScreenedStocks = [];
  bool _isLoading = false;
  String? _error;

  final WalletApiService _apiService = WalletApiService();

  @override
  void initState() {
    super.initState();
    _fetchUsScreenedStocks();
  }

  Future<void> _fetchUsScreenedStocks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final screenedData = await _apiService.fetchUsMarketCapRanking();
      setState(() {
        _usScreenedStocks = screenedData;
      });
    } catch (e) {
      setState(() {
        _error = '미국 장기 스크리닝 데이터를 불러오는 데 실패했습니다: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String formatPrice(dynamic price) {
    if (price == null) {
      return 'N/A';
    }
    double value = _parseToDouble(price);
    final formatter = NumberFormat('#.####');
    return formatter.format(value);
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [

              const Text('미국 장기 스크리닝 종목', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              _isLoading && _usScreenedStocks.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _usScreenedStocks.isEmpty
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : _usScreenedStocks.isEmpty
                          ? const Center(child: Text('미국 장기 스크리닝 데이터가 없습니다.'))
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('티커')),
                                  DataColumn(label: Text('종목명')),
                                  DataColumn(label: Text('현재가')),
                                  DataColumn(label: Text('등락률')),
                                  DataColumn(label: Text('시가총액')),
                                ],
                                rows: _usScreenedStocks.asMap().entries.map<DataRow>((entry) {
                                  var stock = entry.value;
                                  print('[CurrentPriceScreen] Processing stock: $stock'); // Debug print
                                  print('[CurrentPriceScreen] current_price: ${stock['current_price']} (Type: ${stock['current_price'].runtimeType})'); // Debug print
                                  print('[CurrentPriceScreen] market_cap: ${stock['market_cap']} (Type: ${stock['market_cap'].runtimeType})'); // Debug print
                                  final ticker = stock['ticker'];
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        InkWell(
                                          onTap: () {
                                            if (ticker != null) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => StockChartAndDetailsView(ticker: ticker),
                                                ),
                                              );
                                            }
                                          },
                                          child: Text(stock['ticker'] ?? 'N/A'),
                                        ),
                                      ),
                                      DataCell(Text(stock['name'] ?? 'N/A')),
                                      DataCell(Text(formatPrice(stock['price']))),
                                      DataCell(Text('${stock['rate']?.toString() ?? 'N/A'}%')),
                                      DataCell(Text(stock['mcap'] != null ? NumberFormat.compact().format(stock['mcap']) : 'N/A')),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
            ],
          ),
        ),
      ),
    );
  }
}