import 'package:flutter/material.dart';
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
  Map<String, dynamic>? _krProfitData;
  List<dynamic>? _krBalanceData;
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
      _krProfitData = await _apiService.fetchKrProfitData();
      final krBalance = await _apiService.fetchKrBalanceData();
      _krBalanceData = krBalance['stocks'] as List?;

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
          // 홈 화면 (비워둠)
          const Center(child: Text('홈 화면입니다.')),
          // 자산 탭 (주식, 연금 슬라이드)
          PageView(
            children: const [
              AssetStatusScreen(),
              PensionScreen(),
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