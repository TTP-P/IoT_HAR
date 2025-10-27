import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'settings.dart';
import 'utils.dart';
import 'ble.dart';
import 'globals.dart';
import 'dart:io';
import 'dart:math';
import 'har_service.dart';

const int featureWindowSize = 50; // Window size for engineered feature windows
const int featureStepSize = 25; // Step size (stride) for downstream model use

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

  @override
  void initState() {
    super.initState();
    _initializeHAR();
  }

  // Initialize the HAR service
  void _initializeHAR() async {
    bool success = await HARService.initialize();
    setState(() {
      predicted_activity = success 
        ? "HAR ready - waiting for data..." 
        : "HAR initialization failed";
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
    String? prediction,
    required int bufferSize,
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
      
      // Update HAR prediction in UI
      if (prediction != null) {
        predicted_activity = prediction;
      } else {
        predicted_activity ="Collecting data... ($bufferSize/$featureWindowSize samples)";
      }
    });
  }

  // When leaving the home screen, the HAR interpreter and buffer are cleared.
  // Prevents memory leaks or duplicate models being loaded if the user navigates away.
  @override
  void dispose() {
    HARService.dispose();
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
    required this.strideVariability,
    required this.movementConsistency,
    required this.jerkRms,
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
  final double strideVariability;
  final double movementConsistency;
  final double jerkRms;
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
      'accelVert': accelVert,
      'accelHorizMag': accelHorizMag,
      'stride_variability': strideVariability,
      'movement_consistency': movementConsistency,
      'jerk_rms': jerkRms,
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

  List<double>? _gravity;
  List<double>? _previousAccel;
  final List<double> _accelMagWindow = [];
  final List<double> _strideVarWindow = [];
  final List<double> _jerkMagWindow = [];
  int _sampleCount = 0;

  void reset() {
    _gravity = null;
    _previousAccel = null;
    _accelMagWindow.clear();
    _strideVarWindow.clear();
    _jerkMagWindow.clear();
    _sampleCount = 0;
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

    final double strideVar = _updateStdWindow(_accelMagWindow, accelMag);
    final double movementConsistency =
        1 - _updateStdWindow(_strideVarWindow, strideVar);
    final double jerkRms = _updateRmsWindow(_jerkMagWindow, jerkMag);
    final bool isStepBoundary = _sampleCount >= windowSize &&
        ((_sampleCount - windowSize) % stepSize == 0);

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
      strideVariability: strideVar,
      movementConsistency: movementConsistency,
      jerkRms: jerkRms,
      sampleIndex: _sampleCount,
      isStepBoundary: isStepBoundary,
    );
  }

  double _updateStdWindow(List<double> window, double newValue) {
    window.add(newValue);
    if (window.length > windowSize) {
      window.removeAt(0);
    }
    if (window.length < 2) {
      return 0.0;
    }
    final double mean =
        window.reduce((value, element) => value + element) / window.length;
    double variance = 0.0;
    for (final double value in window) {
      final double diff = value - mean;
      variance += diff * diff;
    }
    variance /= window.length;
    return sqrt(variance);
  }

  double _updateRmsWindow(List<double> window, double newValue) {
    window.add(newValue);
    if (window.length > windowSize) {
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

  double _norm(List<double> values) {
    double sumSquares = 0.0;
    for (final double value in values) {
      sumSquares += value * value;
    }
    return sqrt(sumSquares);
  }
}
