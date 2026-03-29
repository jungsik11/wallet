import 'package:flutter/material.dart';
import 'package:app/services/wallet_api_service.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class RaPortfolioScreen extends StatefulWidget {
  const RaPortfolioScreen({Key? key}) : super(key: key);

  @override
  _RaPortfolioScreenState createState() => _RaPortfolioScreenState();
}

class _RaPortfolioScreenState extends State<RaPortfolioScreen> with SingleTickerProviderStateMixin {
  final WalletApiService _apiService = WalletApiService();
  Map<String, dynamic>? _portfolioData;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchPortfolio();
  }

  Future<void> _fetchPortfolio() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _apiService.fetchRaPortfolio();
      if (mounted) {
        setState(() {
          _portfolioData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('오류 발생: $_errorMessage', 
                   style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchPortfolio,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final double rfRate = (_portfolioData!['risk_free_rate'] ?? 0.0) * 100;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('로보어드바이저 AI 포트폴리오', 
                       style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('기준 금리(무위험 수익률): ${rfRate.toStringAsFixed(2)}%', 
                   style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: '최대 수익 (Max Sharpe)'),
              Tab(text: '최소 위험 (Min Vol)'),
            ],
            indicatorWeight: 3,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchPortfolio,
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildPortfolioContent(_portfolioData!['max_sharpe']),
            _buildPortfolioContent(_portfolioData!['min_volatility']),
          ],
        ),
      ),
    );

  }

  Widget _buildPortfolioContent(Map<String, dynamic> data) {
    final Map<String, dynamic> weightsMap = data['weights'];
    final double returns = data['return'] * 100;
    final double volatility = data['volatility'] * 100;
    final double sharpe = data['sharpe_ratio'] ?? (returns / (volatility + 1e-9));

    // Convert weights map to list for the chart
    final List<ChartData> chartData = weightsMap.entries.map((e) {
      return ChartData(e.key, (e.value as num).toDouble() * 100);
    }).toList();


    return RefreshIndicator(
      onRefresh: _fetchPortfolio,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(), // Always scrollable to trigger refresh
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMetricsGrid(returns, volatility, sharpe),
            const SizedBox(height: 32),
            _buildDoughnutChart(chartData, sharpe),
            const SizedBox(height: 32),
          const Text('자산 배분 상세', 
                     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...weightsMap.entries.map((e) => _buildAssetWeightRow(e.key, (e.value as num).toDouble())).toList(),
          const SizedBox(height: 48),
          _buildLogicSection(),
          const SizedBox(height: 24),
          _buildHelpSection(),
          const SizedBox(height: 40),
        ],
      ),
    ),
  );
}

  Widget _buildLogicSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: Colors.greenAccent[100], size: 20),
              const SizedBox(width: 8),
              const Text('포트폴리오 생성 로직', 
                         style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
            ],
          ),
          const SizedBox(height: 16),
          _buildHelpItem('현대 포트폴리오 이론 (MPT)', '자산 간의 상관관계를 분석하여 위험 대비 최대 수익을 낼 수 있는 비중을 계산합니다.'),
          _buildHelpItem('몬테카를로 시뮬레이션', '100,000번 이상의 가상 시나리오 분석을 통해 최적의 포트폴리오를 선정합니다.'),
          _buildHelpItem('안정적 재현성', '고정된 시드(Seed)를 사용하여 동일한 데이터에서는 항상 일관된 결과를 제공합니다.'),
        ],
      ),
    );
  }

  Widget _buildHelpSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueAccent[100], size: 20),
              const SizedBox(width: 8),
              const Text('투자 지표 설명', 
                         style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            ],
          ),
          const SizedBox(height: 16),
          _buildHelpItem('예상 수익률', '과거 데이터를 기반으로 계산된 연간 기대 수익률입니다.'),
          _buildHelpItem('변동성(위험)', '수익률이 얼마나 크게 출렁이는지를 나타내는 지표입니다. 낮을수록 안정적인 투자를 의미합니다.'),
          _buildHelpItem('샤프 지수 (Sharpe Ratio)', '위험 1단위당 얻는 초과 수익입니다. 수치가 높을수록 위험 대비 수익 효율이 좋은 포트폴리오입니다.'),
          _buildHelpItem('무위험 수익률', '원금이 보장되는 안전 자산(국고채 등)의 수익률입니다. 모든 투자의 성과를 비교하는 기준점이 됩니다.'),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[400], height: 1.5)),
        ],
      ),
    );
  }


  Widget _buildMetricsGrid(double returns, double volatility, double sharpe) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildMetricItem('예상 수익률', '${returns.toStringAsFixed(2)}%', 
                           Icons.trending_up, Colors.greenAccent),
          _buildVerticalDivider(),
          _buildMetricItem('변동성(위험)', '${volatility.toStringAsFixed(2)}%', 
                           Icons.warning_amber_rounded, Colors.orangeAccent),
          _buildVerticalDivider(),
          _buildMetricItem('샤프 지수', sharpe.toStringAsFixed(2), 
                           Icons.assessment_outlined, Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 40,
      width: 1,
      color: Colors.grey[700],
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildMetricItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDoughnutChart(List<ChartData> chartData, double sharpe) {
    return SizedBox(
      height: 320, // Increased height to accommodate legend and labels
      child: SfCircularChart(
        margin: const EdgeInsets.all(0),
        legend: Legend(
          isVisible: true, 
          overflowMode: LegendItemOverflowMode.wrap, 
          position: LegendPosition.bottom,
          textStyle: const TextStyle(fontSize: 11, color: Colors.white70),
          alignment: ChartAlignment.center,
        ),
        annotations: <CircularChartAnnotation>[
          CircularChartAnnotation(
            widget: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('평가 지수', style: TextStyle(fontSize: 11, color: Color(0xFFBDBDBD))), // grey[400]
                const Text('Sharpe', style: TextStyle(fontSize: 10, color: Color(0xFF9E9E9E))), // grey[500]
                Text(sharpe.toStringAsFixed(2), 
                     style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              ],
            ),
          )
        ],
        series: <CircularSeries>[
          DoughnutSeries<ChartData, String>(
            dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.name,
            yValueMapper: (ChartData data, _) => data.weight,
            innerRadius: '65%', // Slightly smaller inner radius for cleaner look
            radius: '80%', // Limit outer radius to prevent label overlap
            dataLabelSettings: DataLabelSettings(
              isVisible: true, 
              labelPosition: ChartDataLabelPosition.outside,
              textStyle: const TextStyle(fontSize: 10, color: Colors.white),
              connectorLineSettings: const ConnectorLineSettings(length: '10%'),
            ),
            enableTooltip: true,
            animationDuration: 1500,
            cornerStyle: CornerStyle.bothCurve, // Premium rounded look
          )
        ],
      ),
    );
  }

  Widget _buildAssetWeightRow(String name, double weight) {
    final double weightPercent = weight * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              Text('${weightPercent.toStringAsFixed(1)}%', 
                   style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: weight,
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(
                _getWeightColor(weightPercent),
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }


  Color _getWeightColor(double percent) {
    if (percent > 30) return Colors.blueAccent;
    if (percent > 15) return Colors.cyanAccent;
    return Colors.indigoAccent;
  }
}

class ChartData {
  ChartData(this.name, this.weight);
  final String name;
  final double weight;
}
