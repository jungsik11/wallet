import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> usProfitData;
  final List<dynamic> usBalanceData;
  final Map<String, dynamic> krProfitData;
  final List<dynamic> krBalanceData;
  final Map<String, dynamic> pensionBalanceData;

  const HomeScreen({
    Key? key,
    required this.usProfitData,
    required this.usBalanceData,
    required this.krProfitData,
    required this.krBalanceData,
    required this.pensionBalanceData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 홈 화면 로직 구현
    return const Center(child: Text('홈 화면입니다.'));
  }
}

class _PieData {
  _PieData(this.x, this.y);
  final String x;
  final double y;
}