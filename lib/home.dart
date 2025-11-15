import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'settings.dart';
import 'utils.dart';
import 'ble.dart';
import 'globals.dart';
import 'dart:io';
import 'dart:math';
import 'har_service.dart';
import 'ssc_service.dart';

const int featureWindowSize = 25; // Window size for engineered feature windows
const int featureStepSize = 10; // Step size (stride) for downstream model use

// The home page includes buttons to connect to the respeck, enter capture
// metadata and start recording.

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  //String _counter = "---";
  String accel = "";               // Holds live accelerometer readings (x, y, z)
  String batt_level = "";           // Displays battery level and charging status
  String recording_info = "Not recording"; // Shows recording state
  String predicted_activity = "HAR not initialized"; // HAR model status or prediction

  // Predefined physical activities
  var activities = [
    'Standing',
    'Lying down on left',
    'Lying down right',
    'Lying down back',
    'Lying down on stomach',
    'Normal walking',
    'Ascending stairs',
    'Descending stairs',
    'Shuffle walking',
    'Running',
    'Miscellaneous movements'
  ];
  String selected_activity = "Standing";

  // Predefined social signals
  var social_signals = [
    'Normal',
    'Coughing',
    'Hyperventilating',
    'Talking',
    'Eating',
    'Singing',
    'Laughing'
  ];
  String selected_signal = "Normal";

  bool recording = false;
  bool received_packet = false;

  int recorded_samples = 0;
  DateTime? start_timestamp;

  String filename = "";

  final LightweightFeatureEngineer featureEngineer =
      LightweightFeatureEngineer(
        windowSize: featureWindowSize,
        stepSize: featureStepSize,
      );
  final SscFeatureEngineer sscFeatureEngineer = SscFeatureEngineer();
  final PredictionCoordinator predictionCoordinator = PredictionCoordinator(
    consecutiveThreshold: 1,
    minConfidence: 0.1,
  );

  @override
  void initState() {
    super.initState();
    _initializeHAR();
  }

  // Initialize the HAR service
  void _initializeHAR() async {
    await HARService.initialize();
    await SSCService.initialize();
    setState(() {
      predicted_activity = "HAR ready - waiting for data...";
    });
  }

  // Method to update UI from BLE data processing
  // This function is called by the BLE module whenever new data is received.
  // It updates:
  // - Live accelerometer readings
  // - Battery level and charging status
  // - HAR prediction or model status
  // The setState() call ensures the screen refreshes automatically after updates.

  void updateUI({
    required double x,
    required double y,
    required double z,
    int? batteryLevel,
    bool isCharging = false,
    required int respeckVersion,
    String? harPrediction,
    String? harLabel,
    SscPrediction? sscPrediction,
    required int harBufferSize,
  }) {
    setState(() {
      accel = "x=${x.toStringAsFixed(3)}, y=${y.toStringAsFixed(3)}, z=${z.toStringAsFixed(3)}";
      
      if (respeckVersion == 6) {
        if (isCharging) {
          batt_level = "Battery: $batteryLevel% (charging)";
        } else {
          batt_level = "Battery: $batteryLevel%";
        }
      } else {
        batt_level = "";
      }
      
      final String displayText = predictionCoordinator.resolve(
        harDisplay: harPrediction,
        harLabel: harLabel,
        harBufferSize: harBufferSize,
        harWindowSize: featureWindowSize,
        sscPrediction: sscPrediction,
      );
      predicted_activity = displayText;
    });
  }

  // When leaving the home screen, the HAR interpreter and buffer are cleared.
  // Prevents memory leaks or duplicate models being loaded if the user navigates away.
  @override
  void dispose() {
    HARService.dispose();
    SSCService.dispose();
    predictionCoordinator.reset();
    super.dispose();
  }

  // The UI for the main screen of the app is defined below. Unlike traditional
  // android code, there is no additional XML layout file.

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called to update the UI.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
                onPressed: () {
                  if (respeckUUID == null || respeckUUID == "") {
                    showToast("Please pair with a Respeck first");
                    return;
                  }
                  scanForRespeck(this);
                  print("finished scanning");
                },
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.lightBlue),
                child: const Text('Connect')),
            const SizedBox(height: 20),
            const Text(
              'Acceleration (g)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              accel,
            ),
            Text(
              batt_level,
            ),
            const SizedBox(height: 20),
            const Text(
              'Real-time Activity Recognition',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                predicted_activity,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Activity',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            DropdownButton(
              // Initial Value
              value: selected_activity,
              items: activities.map((String items) {
                return DropdownMenuItem(value: items, child: Text(items));
              }).toList(),
              // After selecting the desired option,it will
              // change button value to selected value
              onChanged: (String? newValue) {
                setState(() {
                  selected_activity = newValue!;
                });
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Social signal',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            DropdownButton(
              // Initial Value
              value: selected_signal,
              items: social_signals.map((String items) {
                return DropdownMenuItem(value: items, child: Text(items));
              }).toList(),
              // After selecting the desired option,it will
              // change button value to selected value
              onChanged: (String? newValue) {
                setState(() {
                  selected_signal = newValue!;
                });
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: record,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightGreen),
                child: const Text('Start recording')),
            const SizedBox(height: 20),
            const Text(
              "Recording status",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              recording_info,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                filename,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () {
                  if (!recording) {
                    return;
                  }
                  recording = false;
                  showToast("Recording stopped");
                },
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.red[200]!),
                child: const Text('Stop recording')),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SettingsPage()),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                child: const Text('Settings')),
          ],
        ),
      ),
    );
  }

  // Start recording respeck data to CSV
  void record() async {
    if (!received_packet) {
      showToast("Please connect to a Respeck first");
      return;
    }
    if (recording) {
      showToast("Already recording");
      return;
    }

    recorded_samples = 0;
    featureEngineer.reset();
    sscFeatureEngineer.reset();
    DateTime now =
        DateTime.now().toUtc(); //use current UTC timestamp for filename
    start_timestamp = now;
    String formattedDate =
        '${DateFormat('yyyy-MM-dd').format(now)}T${DateFormat('kkmmss').format(now)}Z';
    filename =
        'PDIOT_${subjectID}_${sentenceToCamelCase(selected_activity)}_${sentenceToCamelCase(selected_signal)}_${formattedDate}_${respeckUUID?.replaceAll(":", "")}.csv';
    print(filename);

    // create file and write CSV header row
    csvFile = File('${storageFolder?.path}/$filename');
    await csvFile.writeAsString(
        "receivedPhoneTimestamp,respeckTimestamp,packetSeqNum,sampleSeqNum,accelX,accelY,accelZ,gravityX,gravityY,gravityZ,linAccX,linAccY,linAccZ,accelMag,linAccMag,jerkMag,accelVert,accelHorizMag,stride_variability,movement_consistency,jerk_rms\n",
        flush: true);
    showToast("Recording started..");
    recording = true;
  }
}

class FeatureResult {
  FeatureResult({
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gravityX,
    required this.gravityY,
    required this.gravityZ,
    required this.linAccX,
    required this.linAccY,
    required this.linAccZ,
    required this.accelMag,
    required this.linAccMag,
    required this.jerkMag,
    required this.accelVert,
    required this.accelHorizMag,
    required this.jerkVert,
    required this.jerkHorizMag,
    required this.jerkRms,
    required this.jerkInstability,
    required this.vertEnergyRatio,
    required this.horizEnergyRatio,
    required this.highfreqRatio,
    required this.gaitPeriodicity,
    required this.strideVariability,
    required this.movementConsistency,
    required this.vertVelocitySigned,
    required this.vertVelocityTrend,
    required this.lateralBalance,
    required this.sampleIndex,
    required this.isStepBoundary,
  });

  final double accelX;
  final double accelY;
  final double accelZ;
  final double gravityX;
  final double gravityY;
  final double gravityZ;
  final double linAccX;
  final double linAccY;
  final double linAccZ;
  final double accelMag;
  final double linAccMag;
  final double jerkMag;
  final double accelVert;
  final double accelHorizMag;
  final double jerkVert;
  final double jerkHorizMag;
  final double strideVariability;
  final double movementConsistency;
  final double jerkRms;
  final double jerkInstability;
  final double vertEnergyRatio;
  final double horizEnergyRatio;
  final double highfreqRatio;
  final double gaitPeriodicity;
  final double vertVelocitySigned;
  final double vertVelocityTrend;
  final double lateralBalance;
  final int sampleIndex;
  final bool isStepBoundary;

  Map<String, double> toFeatureMap() {
    return {
      'accelX': accelX,
      'accelY': accelY,
      'accelZ': accelZ,
      'gravityX': gravityX,
      'gravityY': gravityY,
      'gravityZ': gravityZ,
      'linAccX': linAccX,
      'linAccY': linAccY,
      'linAccZ': linAccZ,
      'accelMag': accelMag,
      'linAccMag': linAccMag,
      'jerkMag': jerkMag,
      'jerkVert': jerkVert,
      'jerkHorizMag': jerkHorizMag,
      'jerk_rms': jerkRms,
      'jerk_instability': jerkInstability,
      'vert_energy_ratio': vertEnergyRatio,
      'horiz_energy_ratio': horizEnergyRatio,
      'highfreq_ratio': highfreqRatio,
      'gait_periodicity': gaitPeriodicity,
      'stride_variability': strideVariability,
      'movement_consistency': movementConsistency,
      'vert_velocity_signed': vertVelocitySigned,
      'vert_velocity_trend': vertVelocityTrend,
      'lateral_balance': lateralBalance,
    };
  }
}

class LightweightFeatureEngineer {
  LightweightFeatureEngineer({
    this.alpha = 0.98,
    this.eps = 1e-8,
    this.windowSize = featureWindowSize,
    this.stepSize = featureStepSize,
  })  : assert(windowSize > 0),
        assert(stepSize > 0);

  final double alpha;
  final double eps;
  final int windowSize;
  final int stepSize;

  static const int _rollingWindow = 20;
  static const double _samplingFrequency = 12.5;

  List<double>? _gravity;
  List<double>? _previousAccel;
  final List<double> _accelMagWindow = [];
  final List<double> _strideVarWindow = [];
  final List<double> _jerkMagWindow = [];
  final List<double> _jerkInstabilityWindow = [];
  final List<double> _accelVertWindow = [];
  final List<double> _vertVelocityWindow = [];
  int _sampleCount = 0;
  double _vertVelocitySum = 0.0;
  double _previousVertVelocity = 0.0;

  void reset() {
    _gravity = null;
    _previousAccel = null;
    _accelMagWindow.clear();
    _strideVarWindow.clear();
    _jerkMagWindow.clear();
    _jerkInstabilityWindow.clear();
    _accelVertWindow.clear();
    _vertVelocityWindow.clear();
    _sampleCount = 0;
    _vertVelocitySum = 0.0;
    _previousVertVelocity = 0.0;
  }

  FeatureResult processSample(double accelX, double accelY, double accelZ) {
    final List<double> a = [accelX, accelY, accelZ];
    _sampleCount += 1;

    if (_gravity == null) {
      _gravity = List<double>.from(a);
    } else {
      for (int i = 0; i < 3; i++) {
        _gravity![i] = alpha * _gravity![i] + (1 - alpha) * a[i];
      }
    }

    final List<double> gravity = List<double>.from(_gravity!);
    final List<double> linear =
        List<double>.generate(3, (index) => a[index] - gravity[index]);

    final List<double> jerk = List<double>.filled(3, 0.0);
    if (_previousAccel != null) {
      for (int i = 0; i < 3; i++) {
        jerk[i] = a[i] - _previousAccel![i];
      }
    }
    _previousAccel = List<double>.from(a);

    final double accelMag = _norm(a);
    final double linAccMag = _norm(linear);
    final double jerkMag = _norm(jerk);

    double gNorm = _norm(gravity);
    if (gNorm < eps) {
      gNorm = eps;
    }

    final List<double> gHat =
        List<double>.generate(3, (index) => gravity[index] / gNorm);

    final double accelVert =
        a[0] * gHat[0] + a[1] * gHat[1] + a[2] * gHat[2];
    final List<double> accelProj =
        List<double>.generate(3, (index) => gHat[index] * accelVert);
    final List<double> accelHoriz =
        List<double>.generate(3, (index) => a[index] - accelProj[index]);
    final double accelHorizMag = _norm(accelHoriz);

    final double jerkVert =
        jerk[0] * gHat[0] + jerk[1] * gHat[1] + jerk[2] * gHat[2];
    final List<double> jerkProj =
        List<double>.generate(3, (index) => gHat[index] * jerkVert);
    final List<double> jerkHoriz =
        List<double>.generate(3, (index) => jerk[index] - jerkProj[index]);
    final double jerkHorizMag = _norm(jerkHoriz);

    _accelVertWindow.add(accelVert);
    if (_accelVertWindow.length > windowSize) {
      _accelVertWindow.removeAt(0);
    }

    final double strideVar =
        _updateStdWindow(_accelMagWindow, accelMag, _rollingWindow);
    final double movementConsistency =
        1 - _updateStdWindow(_strideVarWindow, strideVar, _rollingWindow);
    final double jerkRms =
        _updateRmsWindow(_jerkMagWindow, jerkMag, _rollingWindow);
    final double jerkInstability =
        _stdMeanCentered(_jerkInstabilityWindow, jerkMag, _rollingWindow);

    _vertVelocityWindow.add(accelVert);
    _vertVelocitySum += accelVert;
    if (_vertVelocityWindow.length > _rollingWindow) {
      _vertVelocitySum -= _vertVelocityWindow.removeAt(0);
    }
    final double vertVelocity = _vertVelocitySum;
    final double vertVelocityTrend = vertVelocity - _previousVertVelocity;
    _previousVertVelocity = vertVelocity;

    final double energyDenominator = (accelMag * accelMag) + eps;
    final double vertEnergyRatio = (accelVert * accelVert) / energyDenominator;
    final double horizEnergyRatio =
        (accelHorizMag * accelHorizMag) / energyDenominator;
    final double highfreqRatio = _bandEnergyRatio(_accelVertWindow);
    final double gaitPeriodicity = _shortAutocorr(_accelVertWindow);
    final double lateralBalance =
        gravity[0].abs() / (gravity[1].abs() + eps);

    final bool isStepBoundary =
        _sampleCount >= windowSize && ((_sampleCount - windowSize) % stepSize == 0);

    return FeatureResult(
      accelX: a[0],
      accelY: a[1],
      accelZ: a[2],
      gravityX: gravity[0],
      gravityY: gravity[1],
      gravityZ: gravity[2],
      linAccX: linear[0],
      linAccY: linear[1],
      linAccZ: linear[2],
      accelMag: accelMag,
      linAccMag: linAccMag,
      jerkMag: jerkMag,
      accelVert: accelVert,
      accelHorizMag: accelHorizMag,
      jerkVert: jerkVert,
      jerkHorizMag: jerkHorizMag,
      jerkRms: jerkRms,
      jerkInstability: jerkInstability,
      vertEnergyRatio: vertEnergyRatio,
      horizEnergyRatio: horizEnergyRatio,
      highfreqRatio: highfreqRatio,
      gaitPeriodicity: gaitPeriodicity,
      strideVariability: strideVar,
      movementConsistency: movementConsistency,
      vertVelocitySigned: vertVelocity,
      vertVelocityTrend: vertVelocityTrend,
      lateralBalance: lateralBalance,
      sampleIndex: _sampleCount,
      isStepBoundary: isStepBoundary,
    );
  }

  double _updateStdWindow(
      List<double> window, double newValue, int maxLength) {
    window.add(newValue);
    if (window.length > maxLength) {
      window.removeAt(0);
    }
    if (window.length < 2) {
      return 0.0;
    }
    double mean = 0.0;
    for (final double value in window) {
      mean += value;
    }
    mean /= window.length;
    double variance = 0.0;
    for (final double value in window) {
      final double diff = value - mean;
      variance += diff * diff;
    }
    variance /= window.length;
    return sqrt(variance);
  }

  double _updateRmsWindow(
      List<double> window, double newValue, int maxLength) {
    window.add(newValue);
    if (window.length > maxLength) {
      window.removeAt(0);
    }
    if (window.isEmpty) {
      return 0.0;
    }
    double sumSquares = 0.0;
    for (final double value in window) {
      sumSquares += value * value;
    }
    return sqrt(sumSquares / window.length);
  }

  double _stdMeanCentered(
      List<double> window, double newValue, int maxLength) {
    window.add(newValue);
    if (window.length > maxLength) {
      window.removeAt(0);
    }
    if (window.length < 2) {
      return 0.0;
    }
    double mean = 0.0;
    for (final double value in window) {
      mean += value;
    }
    mean /= window.length;
    double variance = 0.0;
    for (final double value in window) {
      final double diff = value - mean;
      variance += diff * diff;
    }
    variance /= window.length;
    return sqrt(variance);
  }

  double _bandEnergyRatio(List<double> window) {
    final int n = window.length;
    if (n < 5) {
      return 0.0;
    }
    final double freqResolution = _samplingFrequency / n;
    double low = 0.0;
    double high = 0.0;
    for (int k = 0; k < n; k++) {
      double real = 0.0;
      double imag = 0.0;
      for (int t = 0; t < n; t++) {
        final double angle = 2 * pi * k * t / n;
        final double value = window[t];
        real += value * cos(angle);
        imag -= value * sin(angle);
      }
      final double power = (real * real + imag * imag) / n;
      final double freq = k * freqResolution;
      if (freq >= 0.3 && freq < 2) {
        low += power;
      } else if (freq >= 2 && freq < 5) {
        high += power;
      }
    }
    return high / (low + eps);
  }

  double _shortAutocorr(List<double> window) {
    final int n = min(window.length, _rollingWindow);
    if (n < 5) {
      return 0.0;
    }
    final int start = window.length - n;
    double mean = 0.0;
    for (int i = 0; i < n; i++) {
      mean += window[start + i];
    }
    mean /= n;
    double variance = 0.0;
    for (int i = 0; i < n; i++) {
      final double diff = window[start + i] - mean;
      variance += diff * diff;
    }
    variance /= n;
    if (variance < eps) {
      return 0.0;
    }
    double numerator = 0.0;
    for (int i = 0; i < n - 2; i++) {
      final double v1 = window[start + i] - mean;
      final double v2 = window[start + i + 2] - mean;
      numerator += v1 * v2;
    }
    numerator /= (n - 2);
    return numerator / variance;
  }

  double _norm(List<double> values) {
    double sumSquares = 0.0;
    for (final double value in values) {
      sumSquares += value * value;
    }
    return sqrt(sumSquares);
  }
}

class SscFeatureEngineer {
  SscFeatureEngineer({
    this.samplingFrequency = 12.5,
    this.win = 20,
  })  : _winLong = win * 2,
        _maxJerkHistory = max(50, win * 2);

  final double samplingFrequency;
  final int win;

  static const double _eps = 1e-8;
  static const int _fftWindow = 64;
  static const int _respWindow = 64;
  static const int _breathingDropWindow = 10;
  static const int _jerkShortWindow = 5;
  static const int _jerkLongWindow = 50;
  static const int _linShortWindow = 8;
  static const int _linLongWindow = 32;

  final int _winLong;
  final int _maxJerkHistory;

  final List<double> _jerkMagHistory = <double>[];
  final List<double> _burstFlags = <double>[];
  final List<double> _vertHistory = <double>[];
  final List<double> _diffHistory = <double>[];
  final List<double> _linAccHistory = <double>[];
  final List<double> _linAccStdHistory = <double>[];
  final List<double> _accelMagHistory = <double>[];
  final List<double> _fftEnergyHistory = <double>[];
  final List<int> _zeroCrossHistory = <int>[];
  final List<double> _breathingDropHistory = <double>[];

  double? _previousVertical;
  int? _previousSign;
  double _lastBreathingStability = 1.0;

  void reset() {
    _jerkMagHistory.clear();
    _burstFlags.clear();
    _vertHistory.clear();
    _diffHistory.clear();
    _linAccHistory.clear();
    _linAccStdHistory.clear();
    _accelMagHistory.clear();
    _fftEnergyHistory.clear();
    _zeroCrossHistory.clear();
    _breathingDropHistory.clear();
    _previousVertical = null;
    _previousSign = null;
    _lastBreathingStability = 1.0;
  }

  Map<String, double> process(FeatureResult sample) {
    _appendDouble(_jerkMagHistory, sample.jerkMag, _maxJerkHistory);
    final double rawVertical = sample.accelZ; 
    _appendDouble(_vertHistory, rawVertical, _respWindow);
    final double diffValue = _previousVertical == null
        ? 0.0
        : (rawVertical - _previousVertical!).abs();
    _previousVertical = rawVertical;
    _appendDouble(_diffHistory, diffValue, win);
    _appendDouble(_linAccHistory, sample.linAccMag, _linLongWindow);
    _appendDouble(_accelMagHistory, sample.accelMag, _fftWindow);
    _updateZeroCross(rawVertical);

    final double jerkRms = _rmsTail(_jerkMagHistory, win);
    final double breathingStability = _breathingStability();
    final double rhythmStability = _rhythmStability();
    final double burstDensity = _burstDensity(sample.jerkMag);
    final double energyBurstRatio = _energyBurstRatio(sample.linAccMag);
    final double breathingIntensityVar = _breathingIntensityVariance();
    final double fftEnergy = _fftEnergy();
    final double coughEnergyRatio = _coughEnergyRatio();
    final double dominantRespFreq = _dominantRespFreq();
    final double spectralSharpness = _spectralSharpness();
    final double zeroCrossRate = _zeroCrossRate();
    final double shortEnergyRatio = _shortEnergyRatio();
    final double breathingDisruption = _breathingDisruption(breathingStability);

    return <String, double>{
      'accelX': sample.accelX,
      'accelY': sample.accelY,
      'accelZ': sample.accelZ,
      'accelMag': sample.accelMag,
      'linAccMag': sample.linAccMag,
      'jerkMag': sample.jerkMag,
      'jerk_rms': jerkRms,
      'breathing_stability': breathingStability,
      'rhythm_stability': rhythmStability,
      'burst_density': burstDensity,
      'energy_burst_ratio': energyBurstRatio,
      'breathing_intensity_var': breathingIntensityVar,
      'fft_energy': fftEnergy,
      'zero_cross_rate': zeroCrossRate,
      'dominant_resp_freq': dominantRespFreq,
      'cough_energy_ratio': coughEnergyRatio,
      'breathing_disruption': breathingDisruption,
      'spectral_sharpness': spectralSharpness,
      'short_energy_ratio': shortEnergyRatio,
    };
  }

  double _breathingStability() {
    final int count = min(win, _vertHistory.length);
    if (count <= 1) {
      return 1.0;
    }
    final int start = _vertHistory.length - count;
    double mean = 0.0;
    for (int i = start; i < _vertHistory.length; i++) {
      mean += _vertHistory[i];
    }
    mean /= count;
    double variance = 0.0;
    for (int i = start; i < _vertHistory.length; i++) {
      final double diff = _vertHistory[i] - mean;
      variance += diff * diff;
    }
    variance /= count;
    final double std = sqrt(max(variance, 0.0));
    return (1.0 - std).clamp(0.0, 1.0);
  }

  double _rhythmStability() {
    if (_diffHistory.isEmpty) {
      return 1.0;
    }
    double sum = 0.0;
    for (final double value in _diffHistory) {
      sum += value;
    }
    final double mean = sum / _diffHistory.length;
    return (1.0 - mean).clamp(0.0, 1.0);
  }

  double _burstDensity(double jerkMag) {
    final int count = min(_winLong, _jerkMagHistory.length);
    if (count < 10) {
      _appendDouble(_burstFlags, 0.0, win);
      return _average(_burstFlags).clamp(0.0, 1.0);
    }
    final int start = _jerkMagHistory.length - count;
    double mean = 0.0;
    for (int i = start; i < _jerkMagHistory.length; i++) {
      mean += _jerkMagHistory[i];
    }
    mean /= count;
    double variance = 0.0;
    for (int i = start; i < _jerkMagHistory.length; i++) {
      final double diff = _jerkMagHistory[i] - mean;
      variance += diff * diff;
    }
    variance /= count;
    final double std = sqrt(max(variance, 0.0));
    final double threshold = mean + 2.5 * std;
    final double peak = jerkMag > threshold ? 1.0 : 0.0;
    _appendDouble(_burstFlags, peak, win);
    return _average(_burstFlags).clamp(0.0, 1.0);
  }

  double _coughEnergyRatio() {
    final double shortMean = _meanTail(_jerkMagHistory, _jerkShortWindow, 1);
    final double longMean = _meanTail(_jerkMagHistory, _jerkLongWindow, 10);
    if (longMean.abs() < _eps) {
      return 0.0;
    }
    return (shortMean / longMean).clamp(0.0, 10.0);
  }

  double _dominantRespFreq() {
    if (_vertHistory.length < _respWindow) {
      return 0.0;
    }
    final int start = _vertHistory.length - _respWindow;
    double mean = 0.0;
    for (int i = start; i < _vertHistory.length; i++) {
      mean += _vertHistory[i];
    }
    mean /= _respWindow;
    double variance = 0.0;
    for (int i = start; i < _vertHistory.length; i++) {
      final double diff = _vertHistory[i] - mean;
      variance += diff * diff;
    }
    variance /= _respWindow;
    if (variance < _eps) {
      return 0.0;
    }

    double bestFreq = 0.0;
    double bestPower = 0.0;
    final int n = _respWindow;
    for (int k = 0; k <= n ~/ 2; k++) {
      final double freq = k * samplingFrequency / n;
      if (freq < 0.1 || freq > 2.0) {
        continue;
      }
      double real = 0.0;
      double imag = 0.0;
      for (int t = 0; t < n; t++) {
        final double angle = 2 * pi * k * t / n;
        final double value = _vertHistory[start + t];
        real += value * cos(angle);
        imag -= value * sin(angle);
      }
      final double power = real * real + imag * imag;
      if (power > bestPower) {
        bestPower = power;
        bestFreq = freq;
      }
    }
    return bestFreq.clamp(0.0, 2.0);
  }

  double _spectralSharpness() {
    final int n = min(_fftWindow, _accelMagHistory.length);
    if (n < 16) {
      return 0.0;
    }
    final int start = _accelMagHistory.length - n;
    double mean = 0.0;
    for (int i = start; i < _accelMagHistory.length; i++) {
      mean += _accelMagHistory[i];
    }
    mean /= n;
    double variance = 0.0;
    for (int i = start; i < _accelMagHistory.length; i++) {
      final double diff = _accelMagHistory[i] - mean;
      variance += diff * diff;
    }
    variance /= n;
    if (variance < _eps) {
      return 0.0;
    }

    final int fftLen = n;
    final int freqBins = (fftLen ~/ 2) + 1;
    final List<double> window = List<double>.generate(
      fftLen,
      (int t) => 0.5 - 0.5 * cos(2 * pi * t / (fftLen - 1)),
    );
    final List<double> psd = List<double>.filled(freqBins, 0.0);

    for (int k = 0; k < freqBins; k++) {
      double real = 0.0;
      double imag = 0.0;
      for (int t = 0; t < fftLen; t++) {
        final double angle = 2 * pi * k * t / fftLen;
        final double value = _accelMagHistory[start + t] * window[t];
        real += value * cos(angle);
        imag -= value * sin(angle);
      }
      psd[k] = (real * real + imag * imag) / fftLen;
    }

    double totalPower = 0.0;
    double maxPower = 0.0;
    for (final double power in psd) {
      totalPower += power;
      if (power > maxPower) {
        maxPower = power;
      }
    }
    if (totalPower <= _eps) {
      return 0.0;
    }
    return (maxPower / totalPower).clamp(0.0, 1.0);
  }

  void _updateZeroCross(double value) {
    final int sign = value >= 0 ? 1 : -1;
    int change = 0;
    if (_previousSign != null && sign != _previousSign) {
      change = 1;
    }
    _previousSign = sign;
    _appendInt(_zeroCrossHistory, change, _fftWindow);
  }

  double _zeroCrossRate() {
    if (_zeroCrossHistory.length < 2) {
      return 0.0;
    }
    double sum = 0.0;
    for (final int value in _zeroCrossHistory) {
      sum += value;
    }
    return (sum / _zeroCrossHistory.length).clamp(0.0, 1.0);
  }

  double _shortEnergyRatio() {
    final double shortMean =
        _meanTail(_linAccHistory, _linShortWindow, 2);
    final double longMean =
        _meanTail(_linAccHistory, _linLongWindow, 5);
    if (longMean.abs() < _eps) {
      return 0.0;
    }
    return (shortMean / longMean).clamp(0.0, 10.0);
  }

  double _energyBurstRatio(double linAccMag) {
    final double localMean = _meanTail(_linAccHistory, _linLongWindow, 10);
    if (localMean.abs() < _eps) {
      return 0.0;
    }
    return (linAccMag / localMean).clamp(0.0, 10.0);
  }

  double _breathingIntensityVariance() {
    final int count = min(_linLongWindow, _linAccHistory.length);
    if (count < 5) {
      _appendDouble(_linAccStdHistory, 0.0, _linLongWindow);
      return 0.0;
    }
    final int start = _linAccHistory.length - count;
    double mean = 0.0;
    for (int i = start; i < _linAccHistory.length; i++) {
      mean += _linAccHistory[i];
    }
    mean /= count;
    double variance = 0.0;
    for (int i = start; i < _linAccHistory.length; i++) {
      final double diff = _linAccHistory[i] - mean;
      variance += diff * diff;
    }
    variance /= count;
    final double std = sqrt(max(variance, 0.0));
    _appendDouble(_linAccStdHistory, std, _linLongWindow);
    double maxStd = 0.0;
    for (final double value in _linAccStdHistory) {
      if (value > maxStd) {
        maxStd = value;
      }
    }
    if (maxStd <= _eps) {
      return 0.0;
    }
    return (std / maxStd).clamp(0.0, 1.0);
  }

  double _fftEnergy() {
    final int count = min(_fftWindow, _accelMagHistory.length);
    if (count < 16) {
      _appendDouble(_fftEnergyHistory, 0.0, _fftWindow);
      return 0.0;
    }
    final int start = _accelMagHistory.length - count;
    double energy = 0.0;
    for (int i = start; i < _accelMagHistory.length; i++) {
      final double value = _accelMagHistory[i];
      energy += value * value;
    }
    _appendDouble(_fftEnergyHistory, energy, _fftWindow);
    double maxEnergy = 0.0;
    for (final double value in _fftEnergyHistory) {
      if (value > maxEnergy) {
        maxEnergy = value;
      }
    }
    if (maxEnergy <= _eps) {
      return 0.0;
    }
    return (energy / maxEnergy).clamp(0.0, 1.0);
  }

  double _breathingDisruption(double stability) {
    final double drop = (stability - _lastBreathingStability) < -0.05 ? 1.0 : 0.0;
    _lastBreathingStability = stability;
    _appendDouble(_breathingDropHistory, drop, _breathingDropWindow);
    return _average(_breathingDropHistory).clamp(0.0, 1.0);
  }

  double _meanTail(List<double> source, int length, int minSamples) {
    if (source.isEmpty) {
      return 0.0;
    }
    final int count = min(length, source.length);
    if (count < minSamples) {
      return 0.0;
    }
    final int start = source.length - count;
    double sum = 0.0;
    for (int i = start; i < source.length; i++) {
      sum += source[i];
    }
    return sum / count;
  }

  double _rmsTail(List<double> source, int length) {
    if (source.isEmpty) {
      return 0.0;
    }
    final int count = min(length, source.length);
    if (count == 0) {
      return 0.0;
    }
    final int start = source.length - count;
    double sumSquares = 0.0;
    for (int i = start; i < source.length; i++) {
      final double value = source[i];
      sumSquares += value * value;
    }
    return sqrt(sumSquares / count);
  }

  double _average(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }
    double sum = 0.0;
    for (final double value in values) {
      sum += value;
    }
    return sum / values.length;
  }

  void _appendDouble(List<double> list, double value, int maxLength) {
    list.add(value);
    if (list.length > maxLength) {
      list.removeAt(0);
    }
  }

  void _appendInt(List<int> list, int value, int maxLength) {
    list.add(value);
    if (list.length > maxLength) {
      list.removeAt(0);
    }
  }
}

class PredictionCoordinator {
  PredictionCoordinator({
    required this.consecutiveThreshold,
    required this.minConfidence,
    Set<String>? eligibleHarLabels,
  }) : _eligibleHarLabels = eligibleHarLabels ??
            <String>{
              'Lying back',
              'Lying left',
              'Lying right',
              'Lying stomach',
              'Sitting / Standing',
            };

  final int consecutiveThreshold;
  final double minConfidence;
  final Set<String> _eligibleHarLabels;

  bool _sscActive = false;
  String? _candidateLabel;
  int _candidateCount = 0;
  SscPrediction? _activePrediction;

  void reset() {
    _sscActive = false;
    _candidateLabel = null;
    _candidateCount = 0;
    _activePrediction = null;
  }

  String resolve({
    required String? harDisplay,
    required String? harLabel,
    required int harBufferSize,
    required int harWindowSize,
    required SscPrediction? sscPrediction,
  }) {
    final String harText =
        _formatHarText(harDisplay, harBufferSize, harWindowSize);
    final bool harEligible =
        harLabel != null && _eligibleHarLabels.contains(harLabel);

    if (!harEligible) {
      reset();
      return harText;
    }

    if (sscPrediction != null && sscPrediction.confidence >= minConfidence) {
      if (_candidateLabel == sscPrediction.label) {
        _candidateCount += 1;
      } else {
        _candidateLabel = sscPrediction.label;
        _candidateCount = 1;
      }
    } else {
      _candidateLabel = null;
      _candidateCount = 0;
      if (!_sscActive) {
        return harText;
      }
    }

    if (!_sscActive &&
        _candidateLabel != null &&
        _candidateCount >= consecutiveThreshold &&
        sscPrediction != null &&
        sscPrediction.confidence >= minConfidence) {
      _sscActive = true;
      _activePrediction = sscPrediction;
    }

    if (_sscActive) {
      if (sscPrediction != null && sscPrediction.confidence >= minConfidence) {
        _activePrediction = sscPrediction;
        final String sscText = _formatSsc(_activePrediction!);
        return '$sscText\n$harText';
      }
      _sscActive = false;
      _activePrediction = null;
      return harText;
    }

    return harText;
  }

  String _formatHarText(String? harDisplay, int bufferSize, int window) {
    final String body =
        harDisplay ?? "Collecting data... ($bufferSize/$window samples)";
    return 'HAR - $body';
  }

  String _formatSsc(SscPrediction prediction) {
    final double percent = (prediction.confidence * 100).clamp(0, 100);
    return 'SSC - ${prediction.label} (${percent.toStringAsFixed(1)}%)';
  }
}
