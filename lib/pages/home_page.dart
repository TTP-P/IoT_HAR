import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';

import 'package:fitness_ui_kit/theme/colors.dart';
import '../pages/activity_display_widget.dart';
import '../services/bluetooth_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BluetoothService _bluetoothService = BluetoothService();
  List<FlSpot> _accX = [], _accY = [], _accZ = [];
  List<FlSpot> _gravityX = [], _gravityY = [], _gravityZ = [];
  List<FlSpot> _linearX = [], _linearY = [], _linearZ = [];
  List<FlSpot> _gyroX = [], _gyroY = [], _gyroZ = [];
  double _latestElapsedTime = 0;
  late StreamSubscription<List<int>> _sensorSub;
  Timer? _chartTimer;
  int _startTime = 0;

  // Used to record the user's confirmation status
  bool? _isExerciseMatched;

  // Original system prediction result and overall count
  String _activity = "No device connected";
  bool _detectedExercise = true; // Simulated original system prediction result
  int _correctCount = 0;
  int _incorrectCount = 0;

  // Configuration for 7 actions (in a real project, these can be imported via external configuration)
  final List<String> _actions = [
    "Cycling",
    "WalkDownstairs",
    "Jogging",
    "Lying",
    "Sitting",
    "WalkUpstairs",
    "Walking"
  ];

  // Current predicted action of the system (default is "Sitting" in this example)
  String _currentPredictedAction = "Sitting";

  // Record correct and incorrect counts for each action separately
  late Map<String, int> _actionCorrectCount;
  late Map<String, int> _actionIncorrectCount;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now().millisecondsSinceEpoch;

    // Initialize count maps for each action
    _actionCorrectCount = {for (var a in _actions) a: 0};
    _actionIncorrectCount = {for (var a in _actions) a: 0};

    _setupActivityListeners();
    _setupSensorListener();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: white, // Set overall background color
      body: getBody(),
    );
  }

  @override
  void dispose() {
    _bluetoothService.dispose(); // Ensure resources are released
    _sensorSub.cancel();
    _chartTimer?.cancel();
    super.dispose();
  }

  void _setupActivityListeners() {
    // Listen to the prediction data stream
    _bluetoothService.predictionDataStringStream.listen((dataStr) {
      final parsed = BluetoothService.parsePredictionData(utf8.encode(dataStr));
      if (parsed != _activity) {
        setState(() => _activity = parsed);
      }
    });
  }

  void _setupSensorListener() {
    _sensorSub = _bluetoothService.sensorDataStream.listen((data) {
      if (data.length >= 52) {
        final byteData = Uint8List.fromList(data).buffer.asByteData();
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = (now - _startTime) / 1000;

        setState(() {
          _latestElapsedTime = elapsed;

          // Acceleration data
          _accX.add(FlSpot(elapsed, byteData.getFloat32(4, Endian.little)));
          _accY.add(FlSpot(elapsed, byteData.getFloat32(8, Endian.little)));
          _accZ.add(FlSpot(elapsed, byteData.getFloat32(12, Endian.little)));

          // Gravity data
          _gravityX.add(FlSpot(elapsed, byteData.getFloat32(16, Endian.little)));
          _gravityY.add(FlSpot(elapsed, byteData.getFloat32(20, Endian.little)));
          _gravityZ.add(FlSpot(elapsed, byteData.getFloat32(24, Endian.little)));

          // Linear acceleration
          _linearX.add(FlSpot(elapsed, byteData.getFloat32(28, Endian.little)));
          _linearY.add(FlSpot(elapsed, byteData.getFloat32(32, Endian.little)));
          _linearZ.add(FlSpot(elapsed, byteData.getFloat32(36, Endian.little)));

          // Gyroscope data
          _gyroX.add(FlSpot(elapsed, byteData.getFloat32(40, Endian.little)));
          _gyroY.add(FlSpot(elapsed, byteData.getFloat32(44, Endian.little)));
          _gyroZ.add(FlSpot(elapsed, byteData.getFloat32(48, Endian.little)));

          // Maintain data length
          _trimData(_accX, _accY, _accZ);
          _trimData(_gravityX, _gravityY, _gravityZ);
          _trimData(_linearX, _linearY, _linearZ);
          _trimData(_gyroX, _gyroY, _gyroZ);
        });
      }
    });
  }

  void _trimData(List<FlSpot> x, List<FlSpot> y, List<FlSpot> z) {
    const maxPoints = 100;
    while (x.length > maxPoints) x.removeAt(0);
    while (y.length > maxPoints) y.removeAt(0);
    while (z.length > maxPoints) z.removeAt(0);
  }

  // ===============================
  // Update statistics and record the current predicted action when Yes/No is clicked
  // ===============================
  void _onYesPressed() {
    setState(() {
      _currentPredictedAction = _activity;
      _isExerciseMatched = true;
      if (_detectedExercise == true) {
        _correctCount++;
        _actionCorrectCount[_currentPredictedAction] =
            _actionCorrectCount[_currentPredictedAction]! + 1;
      } else {
        _incorrectCount++;
        _actionIncorrectCount[_currentPredictedAction] =
            _actionIncorrectCount[_currentPredictedAction]! + 1;
      }
    });
  }

  void _onNoPressed() {
    setState(() {
      _currentPredictedAction = _activity;
      _isExerciseMatched = false;
      if (_detectedExercise == false) {
        _correctCount++;
        _actionCorrectCount[_currentPredictedAction] =
            _actionCorrectCount[_currentPredictedAction]! + 1;
      } else {
        _incorrectCount++;
        _actionIncorrectCount[_currentPredictedAction] =
            _actionIncorrectCount[_currentPredictedAction]! + 1;
      }
    });
  }

  // ===============================
  // Build the pie chart (display overall accuracy); clicking it shows the prediction accuracy for 7 actions
  // ===============================
  List<PieChartSectionData> _buildPieChartSections() {
    int total = _correctCount + _incorrectCount;
    if (total == 0) {
      return [
        PieChartSectionData(
          value: 1,
          title: 'N/A',
          color: Colors.grey,
          radius: 80,
          titleStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ];
    }
    double correctPercent = (_correctCount / total) * 100;
    double incorrectPercent = (_incorrectCount / total) * 100;
    return [
      PieChartSectionData(
        value: _correctCount.toDouble(),
        title: '${correctPercent.toStringAsFixed(1)}%',
        gradient: LinearGradient(
            colors: [Colors.green.shade300, Colors.green.shade700]),
        radius: 80,
        titleStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      PieChartSectionData(
        value: _incorrectCount.toDouble(),
        title: '${incorrectPercent.toStringAsFixed(1)}%',
        gradient:
        LinearGradient(colors: [Colors.red.shade300, Colors.red.shade700]),
        radius: 80,
        titleStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    ];
  }

  void _showActionAccuracyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text("Detection accuracy of each action"),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: _buildActionAccuracyBarChart(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("close"),
            )
          ],
        );
      },
    );
  }

  Widget _buildActionAccuracyBarChart() {
    return BarChart(
      BarChartData(
        maxY: 100,
        barGroups: _actions.asMap().entries.map((entry) {
          int index = entry.key;
          String action = entry.value;
          int correct = _actionCorrectCount[action] ?? 0;
          int incorrect = _actionIncorrectCount[action] ?? 0;
          int total = correct + incorrect;
          // If there is no data, show 0%
          double accuracy = total > 0 ? (correct / total * 100) : 0;
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: accuracy,
                width: 15,
                borderRadius: BorderRadius.circular(0),
                color: Colors.blue.shade900,
              ),
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 60,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.toInt();
                if (index >= 0 && index < _actions.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        _actions[index],
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  );
                }
                return Container();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 20,
              getTitlesWidget: (double value, TitleMeta meta) {
                return Text(
                  '${value.toInt()}%',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: FlGridData(
          show: true,
          horizontalInterval: 20,
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildClickableAccuracyPieChart() {
    return GestureDetector(
      onTap: _showActionAccuracyDialog,
      child: _buildAccuracyPieChart(),
    );
  }

  Widget _buildAccuracyPieChart() {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 20),
          width: double.infinity,
          height: 330,
          decoration: BoxDecoration(
            color: white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.4),
                spreadRadius: 4,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 80),
            child: PieChart(
              PieChartData(
                startDegreeOffset: 180,
                sections: _buildPieChartSections(),
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          top: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Detection accuracy",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Colors.green.shade300, Colors.green.shade700]),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    "Correct",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade300, Colors.red.shade700],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    "Incorrect",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSensorChart(
      String title,
      List<FlSpot> x,
      List<FlSpot> y,
      List<FlSpot> z, {
        required double minY,
        required double maxY,
        double width = double.infinity,
      }) {
    return Container(
      width: width,
      height: 220,
      margin: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: black,
                  ),
                ),
                Row(
                  children: [
                    _buildChartLegend("X", Colors.redAccent.shade100),
                    const SizedBox(width: 12),
                    _buildChartLegend("Y", Colors.green.shade100),
                    const SizedBox(width: 12),
                    _buildChartLegend("Z", Colors.blue.shade100),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _getInterval(maxY),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey[200],
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: _getInterval(maxY),
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    _buildLineData(
                      x,
                      Colors.redAccent.shade100.withOpacity(0.8),
                    ),
                    _buildLineData(
                      y,
                      Colors.green.shade100.withOpacity(0.8),
                    ),
                    _buildLineData(
                      z,
                      Colors.blue.shade100.withOpacity(0.8),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartLegend(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  double _getInterval(double max) {
    if (max <= 5) return 1;
    if (max <= 20) return 5;
    return 10;
  }

  LineChartBarData _buildLineData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2,
      belowBarData: BarAreaData(
        show: true,
        color: color.withOpacity(0.1),
      ),
      dotData: FlDotData(show: false),
    );
  }

  Widget getBody() {
    var size = MediaQuery.of(context).size;
    final availableWidth = size.width - 60;

    return SingleChildScrollView(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Welcome Back",
                        style: TextStyle(fontSize: 14, color: black),
                      ),
                      SizedBox(height: 5),
                      Text(
                        "Sopheamen",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: black,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.directions_run, // Running person icon from Material Icons
                        size: 28,
                        color: Colors.black,
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 30),

              // ===== Container that includes ActivityDisplayWidget and Yes/No buttons (vertical layout) =====
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      spreadRadius: 5,
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Prediction action widget (displays "CURRENT ACTIVITY", "No device connected", etc.)
                    ActivityDisplayWidget(bluetoothService: _bluetoothService),

                    const SizedBox(height: 10),

                    // Yes/No buttons: maintain the original horizontal structure
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Yes button
                        InkWell(
                          onTap: _onYesPressed,
                          child: Container(
                            width: 130,
                            height: 45,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  offset: const Offset(0, 3),
                                  blurRadius: 5,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                "Yes",
                                style: TextStyle(fontSize: 13, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // No button
                        InkWell(
                          onTap: _onNoPressed,
                          child: Container(
                            width: 130,
                            height: 45,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.black),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  offset: const Offset(0, 3),
                                  blurRadius: 5,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                "No",
                                style: TextStyle(fontSize: 13, color: Colors.black),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // ===== The above container ensures that "Prediction action" and "Yes/No" are in the same box =====

              const SizedBox(height: 20),

              // Pie chart (click to show the accuracy of the 7 actions)
              Center(child: _buildClickableAccuracyPieChart()),
              const SizedBox(height: 20),

              // Real-time monitoring module: use PageView for horizontal swiping
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 0),
                child: SizedBox(
                  height: 250,
                  child: PageView(
                    controller: PageController(
                      viewportFraction: 1.1,
                    ),
                    pageSnapping: true,
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildSensorChart(
                        "Acceleration",
                        _accX,
                        _accY,
                        _accZ,
                        minY: -30.0,
                        maxY: 30.0,
                        width: availableWidth,
                      ),
                      _buildSensorChart(
                        "Gravity",
                        _gravityX,
                        _gravityY,
                        _gravityZ,
                        minY: -30.0,
                        maxY: 30.0,
                        width: availableWidth,
                      ),
                      _buildSensorChart(
                        "Linear Acceleration",
                        _linearX,
                        _linearY,
                        _linearZ,
                        minY: -30.0,
                        maxY: 30.0,
                        width: availableWidth,
                      ),
                      _buildSensorChart(
                        "Gyroscope",
                        _gyroX,
                        _gyroY,
                        _gyroZ,
                        minY: -30.0,
                        maxY: 30.0,
                        width: availableWidth,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
