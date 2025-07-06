import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'asset_status_screen.dart';
import 'candlestick_chart_screen.dart';
import 'profit_screen.dart';
import 'pension_screen.dart';

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
        brightness: Brightness.dark,
        primaryColor: Colors.grey[900],
        scaffoldBackgroundColor: Colors.grey[900],
        cardColor: Colors.grey[850],
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          elevation: 0,
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        http.get(Uri.parse('http://localhost:8000/calculate_profit?country=US')),
        http.get(Uri.parse('http://localhost:8000/account_balance?country=US')),
        http.get(Uri.parse('http://localhost:8000/calculate_profit?country=KR')),
        http.get(Uri.parse('http://localhost:8000/account_balance?country=KR')),
      ]);

      if (responses.every((response) => response.statusCode == 200)) {
        if (mounted) {
          setState(() {
            _usProfitData = jsonDecode(utf8.decode(responses[0].bodyBytes));
            _usBalanceData = jsonDecode(utf8.decode(responses[1].bodyBytes))['stocks'];
            _krProfitData = jsonDecode(utf8.decode(responses[2].bodyBytes));
            _krBalanceData = jsonDecode(utf8.decode(responses[3].bodyBytes))['stocks'];
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
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.home), text: '홈'),
            Tab(icon: Icon(Icons.show_chart), text: '수익 현황'),
            Tab(icon: Icon(Icons.candlestick_chart), text: '현재가'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: '연금'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const AssetStatusScreen(),
          _buildProfitTab(),
          const CandlestickChartScreen(),
          const PensionScreen(),
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