import 'dart:io';

class ApiConstants {

  static final String baseUrl = Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  static final String calculateProfitUs = '$baseUrl/calculate_profit?country=US';
  static final String accountBalanceUs = '$baseUrl/account_balance?country=US';
  static final String calculateProfitKr = '$baseUrl/calculate_profit?country=KR';
  static final String accountBalanceKr = '$baseUrl/account_balance?country=KR';
  static final String accountBalancePension = '$baseUrl/account_balance_pension';

  static const String ollamaBaseUrl = 'http://localhost:11434';
  static const String ollamaListModels = '$ollamaBaseUrl/api/tags';
}
