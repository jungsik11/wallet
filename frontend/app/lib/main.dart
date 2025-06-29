import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chatbot_screen.dart';
import 'profit_screen.dart';
import 'home_screen.dart';
import 'current_price_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallet App',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.grey[900],
        scaffoldBackgroundColor: Colors.grey[900],
        cardColor: Colors.grey[850],
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        buttonTheme: ButtonThemeData(
          buttonColor: Colors.blueAccent,
          textTheme: ButtonTextTheme.primary,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        colorScheme: ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.tealAccent,
          background: Colors.grey[900]!,
          surface: Colors.grey[850]!,
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
  bool _isLoading = true;
  Map<String, dynamic> _usProfitData = {};
  Map<String, dynamic> _krProfitData = {};
  List<dynamic> _usBalanceData = [];
  List<dynamic> _krBalanceData = [];
  Map<String, dynamic> _portfolioSummary = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('http://127.0.0.1:8000/calculate_profit?country=US')),
        http.get(Uri.parse('http://127.0.0.1:8000/calculate_profit?country=KR')),
        http.get(Uri.parse('http://127.0.0.1:8000/balance')),
        http.get(Uri.parse('http://127.0.0.1:8000/portfolio_summary')),
      ]);

      for (var response in responses) {
        if (response.statusCode != 200) {
          throw Exception('Failed to load data: ${response.request?.url} responded with ${response.statusCode}');
        }
      }

      _usProfitData = jsonDecode(utf8.decode(responses[0].bodyBytes));
      _krProfitData = jsonDecode(utf8.decode(responses[1].bodyBytes));
      
      final balanceData = jsonDecode(utf8.decode(responses[2].bodyBytes));
      _usBalanceData = balanceData['US'] ?? [];
      _krBalanceData = balanceData['KR'] ?? [];
      _portfolioSummary = jsonDecode(utf8.decode(responses[3].bodyBytes));

      setState(() {});

    } catch (e) {
      setState(() {
        _error = '데이터를 불러오는 데 실패했습니다: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showChatbotPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const Dialog(
          child: ChatbotScreen(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.home), text: '홈'),
                Tab(icon: Icon(Icons.show_chart), text: '수익 현황'),
                Tab(icon: Icon(Icons.candlestick_chart), text: '현재가'), // New tab
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!))
                          : HomeScreen(summaryData: _portfolioSummary),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!))
                          : ProfitScreen(
                              usProfitData: _usProfitData,
                              usBalanceData: _usBalanceData,
                              krProfitData: _krProfitData,
                              krBalanceData: _krBalanceData,
                            ),
                  // Current Price Tab
                  const CurrentPriceScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _showChatbotPopup,
              tooltip: '챗봇 열기',
              child: const Icon(Icons.chat),
            )
          : null,
    );
  }
}
