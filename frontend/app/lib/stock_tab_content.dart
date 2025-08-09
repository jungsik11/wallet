import 'package:flutter/material.dart';
import 'package:app/ranking_screen.dart'; // Import RankingScreen
import 'package:app/stock_chart_and_details_view.dart'; // Import StockChartAndDetailsView

class StockTabContent extends StatefulWidget {
  const StockTabContent({Key? key}) : super(key: key);

  @override
  _StockTabContentState createState() => _StockTabContentState();
}

class _StockTabContentState extends State<StockTabContent> with SingleTickerProviderStateMixin {
  late TabController _subTabController;

  // For now, a fixed ticker for testing. This will eventually come from another screen.
  final String _currentTicker = 'PLTR'; // Example ticker

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _subTabController,
          labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(width: 3.0, color: Theme.of(context).colorScheme.primary), // Use primary color for indicator
            insets: const EdgeInsets.symmetric(horizontal: 16.0), // Add horizontal padding to indicator
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 16.0), // Add padding to tab labels
          // backgroundColor: Theme.of(context).cardColor, // Optional: Change background color of TabBar
          // dividerColor: Theme.of(context).dividerColor, // Optional: Add divider color
          tabs: const [
            Tab(text: '차트'),
            Tab(text: '상승 종목'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              // Chart Tab Content
              StockChartAndDetailsView(ticker: _currentTicker), // Use StockChartAndDetailsView
              // Ranking Tab Content
              const RankingScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
