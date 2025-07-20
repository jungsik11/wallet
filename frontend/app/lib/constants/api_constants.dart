class ApiConstants {
  static const String baseUrl = 'http://10.0.2.2:8000';
  static const String calculateProfitUs = '$baseUrl/calculate_profit?country=US';
  static const String accountBalanceUs = '$baseUrl/account_balance?country=US';
  static const String calculateProfitKr = '$baseUrl/calculate_profit?country=KR';
  static const String accountBalanceKr = '$baseUrl/account_balance?country=KR';
  static const String accountBalancePension = '$baseUrl/account_balance_pension';

  static const String ollamaBaseUrl = 'http://10.0.2.2:11434';
  static const String ollamaListModels = '$ollamaBaseUrl/api/tags';
}
