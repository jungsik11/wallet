import 'package:flutter/material.dart';
import 'package:app/stock_trading_screen.dart';
import 'package:app/presentation/app_theme.dart';

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
      home: const StockTradingScreen(ticker: 'EEIQ'),
    );
  }
}
