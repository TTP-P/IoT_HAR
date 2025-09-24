import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class SensorChartCard extends StatelessWidget {
  final String title;
  final List<FlSpot> dataX;
  final List<FlSpot> dataY;
  final List<FlSpot> dataZ;
  final double minY;
  final double maxY;
  final double latestTime;

  const SensorChartCard({
    Key? key,
    required this.title,
    required this.dataX,
    required this.dataY,
    required this.dataZ,
    required this.minY,
    required this.maxY,
    required this.latestTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: LineChart(
                LineChartData(
                  minX: latestTime > 30 ? latestTime - 30 : 0,
                  maxX: latestTime + 1,
                  minY: minY,
                  maxY: maxY,
                  // Retain the existing chart configuration and adjust colors to match the homepage theme
                  lineBarsData: [
                    _buildLineData(dataX, Colors.red),
                    _buildLineData(dataY, Colors.green),
                    _buildLineData(dataZ, Colors.blue),
                  ],
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) => Text(
                          '${value.toInt()}s',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        interval: 10,
                      ),
                    ),
                    leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildLineData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color.withOpacity(0.6),
      barWidth: 1.5,
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }
}