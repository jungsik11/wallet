import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chatbot_screen.dart';
import 'profit_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCountry = 'US';

  bool _isLoading = true;
  Map<String, dynamic> _usProfitData = {};
  Map<String, dynamic> _krProfitData = {};
  Map<String, double> _usCurrentPrices = {};
  Map<String, double> _krCurrentPrices = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      // API 호출을 병렬로 실행합니다.
      final responses = await Future.wait([
        http.get(Uri.parse('http://127.0.0.1:8000/calculate_profit?country=US')),
        http.get(Uri.parse('http://127.0.0.1:8000/calculate_profit?country=KR')),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        _usProfitData = jsonDecode(utf8.decode(responses[0].bodyBytes));
        _krProfitData = jsonDecode(utf8.decode(responses[1].bodyBytes));

        // Fetch current prices for all stocks
        await _fetchCurrentPrices();

        setState(() {});
      } else {
        // 에러 메시지를 생성합니다.
        final usError = responses[0].statusCode != 200 ? 'US data error: ${responses[0].statusCode}' : '';
        final krError = responses[1].statusCode != 200 ? 'KR data error: ${responses[1].statusCode}' : '';
        throw Exception('$usError $krError'.trim());
      }
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

  Future<void> _fetchCurrentPrices() async {
    // Helper function to fetch prices for a given country and data
    Future<Map<String, double>> fetchPricesForCountry(Map<String, dynamic> profitData, String country) async {
      final Map<String, double> prices = {};
      if (profitData['stocks'] != null) {
        for (var stockMap in profitData['stocks']) {
          final ticker = stockMap.keys.first;
          final stockHolding = stockMap.values.first;
          if (stockHolding['holdings']['total'] > 0) {
            try {
              final response = await http.get(Uri.parse('http://127.0.0.1:8000/current_price/$country/$ticker'));
              if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                prices[ticker] = data['current_price'];
              } else {
                prices[ticker] = 0.0; // Error case
              }
            } catch (e) {
              prices[ticker] = 0.0; // Error case
            }
            // Add a small delay to avoid hitting rate limits.
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }
      return prices;
    }

    // Fetch for both countries in parallel
    final results = await Future.wait([
      fetchPricesForCountry(_usProfitData, 'US'),
      fetchPricesForCountry(_krProfitData, 'KR'),
    ]);

    _usCurrentPrices = results[0];
    _krCurrentPrices = results[1];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showChatbotPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.7,
            child: const ChatbotScreen(),
          ),
        );
      },
    );
  }

  Widget _buildProfitScreen() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchData,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    
    final profitData = _selectedCountry == 'US' ? _usProfitData : _krProfitData;
    final currentPrices = _selectedCountry == 'US' ? _usCurrentPrices : _krCurrentPrices;

    return ProfitScreen(
      country: _selectedCountry,
      profitData: profitData,
      currentPrices: currentPrices,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Wallet'),
        actions: [
          DropdownButton<String>(
            value: _selectedCountry,
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedCountry = newValue;
                });
              }
            },
            items: <String>['US', 'KR']
                .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            iconEnabledColor: Colors.white,
          ),
          const SizedBox(width: 16),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.home), text: '홈'),
            Tab(icon: Icon(Icons.show_chart), text: '수익 현황'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const Center(
            child: Text('안녕하세요! 챗봇을 이용해보세요.'),
          ),
          _buildProfitScreen(),
        ],
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
