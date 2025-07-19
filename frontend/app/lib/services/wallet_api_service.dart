import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:app/constants/api_constants.dart';

class WalletApiService {
  Future<Map<String, dynamic>> fetchUsProfitData() async {
    final response = await http.get(Uri.parse(ApiConstants.calculateProfitUs));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load US profit data: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchUsBalanceData() async {
    final response = await http.get(Uri.parse(ApiConstants.accountBalanceUs));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load US balance data: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchKrProfitData() async {
    final response = await http.get(Uri.parse(ApiConstants.calculateProfitKr));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load KR profit data: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchKrBalanceData() async {
    final response = await http.get(Uri.parse(ApiConstants.accountBalanceKr));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load KR balance data: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchPensionBalanceData() async {
    final response = await http.get(Uri.parse(ApiConstants.accountBalancePension));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load Pension balance data: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchAccountBalance() async {
    final response = await http.get(Uri.parse(ApiConstants.accountBalanceUs)); // Assuming this is for US assets
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load account balance: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchAccountBalancePension() async {
    final response = await http.get(Uri.parse(ApiConstants.accountBalancePension));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load pension account balance: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchOhlcvData(String ticker, String timeframe) async {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/ohlcv?ticker=$ticker&timeframe=$timeframe'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load OHLCV data: ${response.statusCode}');
    }
  }
}
