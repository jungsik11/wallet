import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:app/asset_status_screen.dart';
import 'package:app/candlestick_chart_screen.dart';
import 'package:app/profit_screen.dart';
import 'package:app/pension_screen.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Wallet',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.purple,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.grey[200],
        cardColor: Colors.grey[100],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[300],
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        tabBarTheme: TabBarTheme(
          indicatorColor: Theme.of(context).colorScheme.secondary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey[600],
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _usProfitData;
  List<dynamic>? _usBalanceData;
  Map<String, dynamic>? _krProfitData;
  List<dynamic>? _krBalanceData;
  bool _isLoading = true;
  String? _errorMessage;

  double _totalCombinedCash = 0.0;
  double _totalCombinedStockValuation = 0.0;

  double _usCash = 0.0;
  double _usStockValuation = 0.0;
  double _krCash = 0.0;
  double _krStockValuation = 0.0;
  double _pensionCash = 0.0;
  double _pensionStockValuation = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final responses = await Future.wait([
        http.get(Uri.parse('http://10.0.2.2:8000/calculate_profit?country=US')),
        http.get(Uri.parse('http://10.0.2.2:8000/account_balance?country=US')),
        http.get(Uri.parse('http://10.0.2.2:8000/calculate_profit?country=KR')),
        http.get(Uri.parse('http://10.0.2.2:8000/account_balance?country=KR')),
        http.get(Uri.parse('http://10.0.2.2:8000/account_balance_pension')),
      ]);

      if (responses.every((response) => response.statusCode == 200)) {
        if (mounted) {
          setState(() {
            _usProfitData = jsonDecode(utf8.decode(responses[0].bodyBytes));
            final usBalance = jsonDecode(utf8.decode(responses[1].bodyBytes));
            _usBalanceData = usBalance['stocks'] as List?;
            _krProfitData = jsonDecode(utf8.decode(responses[2].bodyBytes));
            final krBalance = jsonDecode(utf8.decode(responses[3].bodyBytes));
            _krBalanceData = krBalance['stocks'] as List?;
            final pensionBalance = jsonDecode(utf8.decode(responses[4].bodyBytes));

            // Calculate US account cash and stock valuation
            _usCash = (usBalance['cash']?['krw'] ?? 0).toDouble() + (usBalance['cash']?['usd_in_krw'] ?? 0).toDouble();
            _usStockValuation = (usBalance['stocks'] as List? ?? []).fold<double>(0.0, (sum, stock) => sum + (stock['valuation'] as num).toDouble());

            // Calculate KR account cash and stock valuation
            _krCash = (krBalance['cash']?['krw'] ?? 0).toDouble() + (krBalance['cash']?['usd_in_krw'] ?? 0).toDouble();
            _krStockValuation = (krBalance['stocks'] as List? ?? []).fold<double>(0.0, (sum, stock) => sum + (stock['valuation'] as num).toDouble());

            // Calculate Pension account cash and stock valuation
            _pensionCash = (pensionBalance['cash']?['krw'] ?? 0).toDouble() + (pensionBalance['cash']?['usd_in_krw'] ?? 0).toDouble();
            _pensionStockValuation = (pensionBalance['stocks'] as List? ?? []).fold<double>(0.0, (sum, stock) => sum + (stock['valuation'] as num).toDouble());

            // Calculate total combined cash and stock valuation
            _totalCombinedCash = _krCash + _pensionCash;
            _totalCombinedStockValuation = _krStockValuation + _pensionStockValuation;
          });
        }
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
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
    final currencyFormat = NumberFormat.currency(locale: 'ko_KR', symbol: '₩');

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.home), text: '홈'),
            Tab(icon: Icon(Icons.bar_chart), text: '주식'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: '연금'),
            Tab(icon: Icon(Icons.show_chart), text: '수익 현황'),
            Tab(icon: Icon(Icons.candlestick_chart), text: '현재가'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(child: Text(_errorMessage!))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('총 자산', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 10),
                          ListTile(
                            title: const Text('총 자산'),
                            trailing: Text(currencyFormat.format(_totalCombinedCash + _totalCombinedStockValuation)),
                          ),
                          const Divider(),
                          Text('주식 계좌', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 10),
                          ListTile(
                            title: const Text('총 자산'),
                            trailing: Text(currencyFormat.format(_krCash +  _krStockValuation)),
                          ),
                          const Divider(),
                          Text('연금 계좌', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 10),
                          ListTile(
                            title: const Text('총 자산'),
                            trailing: Text(currencyFormat.format(_pensionCash + _pensionStockValuation)),
                          ),
                        ],
                      ),
                    ),
          const AssetStatusScreen(),
          const PensionScreen(),
          _buildProfitTab(),
          const CandlestickChartScreen(),
        ],
      ),
    );
  }

  Widget _buildProfitTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    if (_usProfitData == null || _usBalanceData == null || _krProfitData == null || _krBalanceData == null) {
      return const Center(child: Text('No data available'));
    }

    return ProfitScreen(
      usProfitData: _usProfitData!,
      usBalanceData: _usBalanceData!,
      krProfitData: _krProfitData!,
      krBalanceData: _krBalanceData!,
    );
  }
}