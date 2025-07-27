import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:app/asset_status_screen.dart';
import 'package:app/candlestick_chart_screen.dart';
import 'package:app/profit_screen.dart';
import 'package:app/pension_screen.dart';
import 'package:app/presentation/app_theme.dart';
import 'package:app/constants/api_constants.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:app/chatbot_screen.dart'; // Add this line
import 'package:app/responsive_text.dart'; // Add this line
import 'package:app/home_screen.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Wallet',
      theme: appTheme,
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
  double? _usExchangeRate;
  Map<String, dynamic>? _krProfitData;
  List<dynamic>? _krBalanceData;
  double? _krExchangeRate;
  Map<String, dynamic>? _pensionBalanceData;
  bool _isLoading = true;
  String? _errorMessage;

  final WalletApiService _apiService = WalletApiService();

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
      _usProfitData = await _apiService.fetchUsProfitData();
      final usBalance = await _apiService.fetchUsBalanceData();
      _usBalanceData = usBalance['stocks'] as List?;
      _usExchangeRate = usBalance['exchange_rate'] as double?;
      _krProfitData = await _apiService.fetchKrProfitData();
      final krBalance = await _apiService.fetchKrBalanceData();
      _krBalanceData = krBalance['stocks'] as List?;
      _krExchangeRate = krBalance['exchange_rate'] as double?;
      _pensionBalanceData = await _apiService.fetchPensionBalanceData();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
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
            Tab(icon: Icon(Icons.account_balance_wallet), text: '자산'), // 새로운 자산 탭
            Tab(icon: Icon(Icons.show_chart), text: '수익 현황'),
            Tab(icon: Icon(Icons.candlestick_chart), text: '현재가'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHomeTab(),
          // 자산 탭 (주식, 연금 슬라이드)
          PageView(
            children: [
              _buildAssetStatusScreen(),
              _buildPensionScreen(),
            ],
          ),
          // 수익 현황 탭
          _buildProfitTab(),
          // 현재가 탭
          const CandlestickChartScreen(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                height: MediaQuery.of(context).size.height * 0.7,
                child: const ChatbotScreen(),
              ),
            ),
          );
        },
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }

  Widget _buildHomeTab() {
    if (_isLoading || _usProfitData == null || _usBalanceData == null || _krProfitData == null || _krBalanceData == null || _pensionBalanceData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }
    // HomeScreen에 필요한 데이터 전달
    return HomeScreen(
      usProfitData: _usProfitData!,
      usBalanceData: _usBalanceData!,
      krProfitData: _krProfitData!,
      krBalanceData: _krBalanceData!,
      pensionBalanceData: _pensionBalanceData!,
      usExchangeRate: _usExchangeRate, // Add this line
    );
  }

  Widget _buildAssetStatusScreen() {
    if (_isLoading || _usBalanceData == null || _krBalanceData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }
    // AssetStatusScreen에 필요한 데이터 전달
    return AssetStatusScreen(
      usBalanceData: _usBalanceData!,
      krBalanceData: _krBalanceData!,
    );
  }

  Widget _buildPensionScreen() {
    if (_isLoading || _pensionBalanceData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }
    // PensionScreen에 필요한 데이터 전달
    return PensionScreen(
      pensionBalanceData: _pensionBalanceData!,
    );
  }

  Widget _buildProfitTab() {
    if (_isLoading || _usProfitData == null || _usBalanceData == null || _krProfitData == null || _krBalanceData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    return ProfitScreen(
      usProfitData: _usProfitData!,
      usBalanceData: _usBalanceData!,
      krProfitData: _krProfitData!,
      krBalanceData: _krBalanceData!,
      usExchangeRate: _usExchangeRate!,
      krExchangeRate: _krExchangeRate!,
    );
  }
}
