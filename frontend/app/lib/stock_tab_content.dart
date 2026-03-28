import 'package:flutter/material.dart';
import 'package:app/ranking_screen.dart'; // Import RankingScreen
import 'package:app/stock_chart_and_details_view.dart'; // Import StockChartAndDetailsView
import 'package:app/current_price_screen.dart'; // Import CurrentPriceScreen

class StockTabContent extends StatefulWidget {
  const StockTabContent({Key? key}) : super(key: key);

  @override
  _StockTabContentState createState() => _StockTabContentState();
}

class _StockTabContentState extends State<StockTabContent> with SingleTickerProviderStateMixin {
  late TabController _subTabController;
  String _selectedRankingType = 'top_gainers'; // State for the SegmentedButton
  int _selectedIndex = 0; // Track selected sub-tab index

  // For now, a fixed ticker for testing. This will eventually come from another screen.
  String _currentTicker = 'PLTR'; // Example ticker

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
    _subTabController.addListener(() {
      setState(() {
        _selectedIndex = _subTabController.index;
      });
    });
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  void _onTickerSelected(String ticker) {
    setState(() {
      _currentTicker = ticker;
    });
    _subTabController.animateTo(0);
  }

  void _onRankingTypeChanged(String newType) {
    setState(() {
      _selectedRankingType = newType;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: kToolbarHeight), // Add this line
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
            Tab(text: '현재가'),
          ],
        ),
        // SegmentedButton moved here, directly below the TabBar
        if (_selectedIndex == 1) // Conditionally render only for "상승 종목" tab
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'top_gainers',
                  label: Text('등락률 상위'),
                ),
                ButtonSegment<String>(
                  value: 'market_cap',
                  label: Text('시가총액 상위'),
                ),
              ],
              selected: <String>{_selectedRankingType},
              onSelectionChanged: (Set<String> newSelection) {
                _onRankingTypeChanged(newSelection.first);
              },
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              // Chart Tab Content
              StockChartAndDetailsView(ticker: _currentTicker), // Use StockChartAndDetailsView
              // Ranking Tab Content
              RankingScreen(
                onTickerSelected: _onTickerSelected,
                selectedRankingType: _selectedRankingType, // Pass the state
                onRankingTypeChanged: _onRankingTypeChanged, // Pass the callback
              ),
              // Current Price Tab Content
              CurrentPriceScreen(onTickerSelected: _onTickerSelected, ticker: _currentTicker),
            ],
          ),
        ),
      ],
    );
  }
}
