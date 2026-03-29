import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:app/constants/api_constants.dart';

class WalletApiService {
  Future<Map<String, dynamic>> fetchAllProfitData(String country) async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/all_profit_data?country=$country'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load all profit data for $country: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchAllBalanceData() async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/all_balance_data'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load all balance data: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchOhlcvData(String ticker, String timeframe) async {
    await Future.delayed(const Duration(milliseconds: 200)); // Add delay
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/ohlcv/$timeframe?ticker=$ticker'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load OHLCV data: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> fetchRankingData() async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/ranking/charts'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load ranking data: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchStockDetail(String ticker) async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/stock/$ticker'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load stock detail for $ticker: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchOrderbook(String ticker) async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/orderbook/$ticker'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load order book for $ticker: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> fetchUsLongTermScreenedStocks() async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/screener/us-long-term'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load US long-term screened stocks: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> fetchUsMarketCapRanking() async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/screener/us-market-cap-ranking'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load US market cap ranking: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchCurrentPrice(String ticker) async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/price/$ticker'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load current price for $ticker: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchRaPortfolio() async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/ra/portfolio'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load RA portfolio: ${response.statusCode}');
    }
  }
}
