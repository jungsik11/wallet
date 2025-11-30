import 'package:flutter/material.dart';


import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:app/asset_status_screen.dart';
import 'package:app/profit_screen.dart';
import 'package:app/pension_screen.dart';
import 'package:app/presentation/app_theme.dart';
import 'package:app/constants/api_constants.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:app/chatbot_screen.dart'; // Add this line
import 'package:app/home_screen.dart';
import 'package:app/ranking_screen.dart';
import 'package:app/stock_tab_content.dart'; // Add this line
import 'package:app/stock_chart_and_details_view.dart';
import 'package:app/current_price_screen.dart';


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
      debugShowCheckedModeBanner: false,
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
  int _selectedIndex = 0; // Add this line
  Map<String, Map<String, dynamic>>? _usProfitData; // Map of year to profit data
  Map<String, dynamic>? _usBalanceData;
  double? _usExchangeRate;
  Map<String, Map<String, dynamic>>? _krProfitData; // Map of year to profit data
  Map<String, dynamic>? _krBalanceData;
  Map<String, dynamic>? _pensionBalanceData;
  bool _isLoading = true;
  String? _errorMessage;

  final WalletApiService _apiService = WalletApiService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedIndex = _tabController.index;
      });
    });
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
      // Fetch all data in parallel using the new aggregated endpoints
      final results = await Future.wait([
        _apiService.fetchAllProfitData('US'),
        _apiService.fetchAllProfitData('KR'),
        _apiService.fetchAllBalanceData(),
      ]);

      // Process results
      _usProfitData = (results[0] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as Map<String, dynamic>),
      );
      _krProfitData = (results[1] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as Map<String, dynamic>),
      );
      
      final allBalanceData = results[2] as Map<String, dynamic>;
      _usBalanceData = allBalanceData['us_balance_data'] as Map<String, dynamic>;
      _krBalanceData = allBalanceData['kr_balance_data'] as Map<String, dynamic>;
      _pensionBalanceData = allBalanceData['pension_balance_data'] as Map<String, dynamic>;
      
      _usExchangeRate = (_usBalanceData!['exchange_rate'] as num?)?.toDouble();

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
      
      bottomNavigationBar: Builder( // Use Builder to get a new context for MediaQuery
        builder: (BuildContext innerContext) {
          final double screenWidth = MediaQuery.of(innerContext).size.width;
          final double tabWidth = screenWidth / 10; // Adjust to show more tabs

          return Material(
            color: Theme.of(innerContext).colorScheme.surface,
            elevation: 8.0,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Theme.of(innerContext).colorScheme.primary,
              unselectedLabelColor: Theme.of(innerContext).colorScheme.onSurface.withOpacity(0.6),
              indicatorColor: Theme.of(innerContext).colorScheme.primary,
              tabs: [
                SizedBox(width: tabWidth, child: const Tab(icon: Icon(Icons.home), text: '홈')),
                SizedBox(width: tabWidth, child: const Tab(icon: Icon(Icons.bar_chart), text: '주식 상세')),
                SizedBox(width: tabWidth, child: const Tab(icon: Icon(Icons.account_balance_wallet), text: '자산/연금')),
                SizedBox(width: tabWidth, child: const Tab(icon: Icon(Icons.trending_up), text: '수익 현황')),
                SizedBox(width: tabWidth, child: const Tab(icon: Icon(Icons.more_horiz), text: '더미 1')),
                SizedBox(width: tabWidth, child: const Tab(icon: Icon(Icons.more_horiz), text: '더미 2')),
                SizedBox(width: tabWidth, child: const Tab(icon: Icon(Icons.more_horiz), text: '더미 3')),
              ],
            ),
          );
        },
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const AlwaysScrollableScrollPhysics(), // Added this line
        children: [
          _buildHomeTab(),
          // New Stock Detail Screen (moved)
          const StockTabContent(),
          // 자산 탭 (주식, 연금 슬라이드)
          PageView(
            children: [
              _buildAssetStatusScreen(),
              _buildPensionScreen(),
            ],
          ),
          // 수익 현황 탭
          _buildProfitTab(),
          // New dummy tabs
          Center(child: Text('Dummy Tab 1')),
          Center(child: Text('Dummy Tab 2')),
          Center(child: Text('Dummy Tab 3')),
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
      usBalanceData: (_usBalanceData!['stocks'] as List<dynamic>?) ?? [],
      krProfitData: _krProfitData!,
      krBalanceData: (_krBalanceData!['stocks'] as List<dynamic>?) ?? [],
      pensionBalanceData: _pensionBalanceData!,
      usExchangeRate: _usExchangeRate,
      onRefresh: _fetchData,
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
      onRefresh: _fetchData,
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
      onRefresh: _fetchData,
    );
  }

  Widget _buildProfitTab() {
    if (_isLoading || _usProfitData == null || _usBalanceData == null || _krProfitData == null || _krBalanceData == null || _usExchangeRate == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    return ProfitScreen(
      usProfitData: _usProfitData!,
      usBalanceData: (_usBalanceData!['stocks'] as List<dynamic>?) ?? [],
      krProfitData: _krProfitData!,
      krBalanceData: (_krBalanceData!['stocks'] as List<dynamic>?) ?? [],
      usExchangeRate: _usExchangeRate!,
      krExchangeRate: null, // krExchangeRate is no longer needed
    );
  }
}