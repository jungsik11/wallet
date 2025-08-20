import 'package:flutter/material.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:intl/intl.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({Key? key}) : super(key: key);

  @override
  _RankingScreenState createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> with AutomaticKeepAliveClientMixin<RankingScreen> {
  List<dynamic> _rankingData = [];
  bool _isLoading = true;
  String? _error;

  final WalletApiService _apiService = WalletApiService();
  final NumberFormat _numberFormat = NumberFormat('#,###');

  String formatPrice(dynamic price) {
    if (price == null) {
      return 'N/A';
    }
    // Safely parse the dynamic price to a double
    double? value = double.tryParse(price.toString());

    if (value == null) {
      return 'N/A'; // Return N/A if parsing fails
    }

    // Use NumberFormat to remove unnecessary trailing zeros
    // The pattern '#.####' means show up to 4 decimal places, but remove trailing zeros.
    // If you need more decimal places, adjust the number of #.
    final formatter = NumberFormat('#.####');
    return formatter.format(value);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchRankingData();
  }

  Future<void> _fetchRankingData() async {
    if (_rankingData.isEmpty) {
      setState(() {
        _isLoading = true;
      });
    }
    setState(() {
      _error = null;
    });

    try {
      final rankingData = await _apiService.fetchRankingData();
      if (mounted) {
        setState(() {
          _rankingData = rankingData;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '순위 데이터를 불러오는 데 실패했습니다: ${e.toString()}';
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchRankingData,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: kToolbarHeight), // Add this line
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const Center(child: Text('아래로 당겨서 새로고침하세요.')),
        ],
      );
    }

    if (_rankingData.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: kToolbarHeight), // Add this line
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          const Center(child: Text('순위 데이터가 없습니다.')),
          const Center(child: Text('아래로 당겨서 새로고침하세요.')),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: kToolbarHeight), // Add this line
          DataTable(
            columns: const [
              DataColumn(label: Text('순위'), columnWidth: FixedColumnWidth(50)),
              DataColumn(label: Text('종목명')),
              DataColumn(label: Text('현재가'), columnWidth: FixedColumnWidth(120)),
              DataColumn(label: Text('등락률')),
              DataColumn(label: Text('거래량')),
            ],
            rows: _rankingData.asMap().entries.map((entry) {
              int index = entry.key;
              var stock = entry.value;
              
              // Safely parse values that might be String or num from the API
              final double diff = double.tryParse(stock['diff']?.toString() ?? '') ?? 0.0;
              final double rate = double.tryParse(stock['rate']?.toString() ?? '') ?? 0.0;
              final int volume = int.tryParse(stock['volume']?.toString() ?? '') ?? 0;
              final String price = formatPrice(stock['price']);

              return DataRow(
                cells: [
                  DataCell(Text((index + 1).toString())),
                  DataCell(
                    SizedBox(
                      width: 100, // Adjust this width as needed
                      child: Text(
                        stock['name'] ?? 'N/A',
                        maxLines: 2, // Allow text to wrap to 2 lines
                        overflow: TextOverflow.ellipsis, // Show ellipsis if text overflows 2 lines
                      ),
                    ),
                  ),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(price),
                        Text(
                          '(${diff.toStringAsFixed(2)}) ',
                          style: TextStyle(color: diff >= 0 ? Colors.green : Colors.red, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      '${rate.toStringAsFixed(2)}%',
                      style: TextStyle(color: rate >= 0 ? Colors.green : Colors.red),
                    ),
                  ),
                  DataCell(Text(_numberFormat.format(volume))),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
