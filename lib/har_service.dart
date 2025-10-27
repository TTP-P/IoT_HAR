import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

// Service class to handle Human Activity Recognition (HAR) using TensorFlow Lite
class HARService {
  HARService._();

  static Interpreter? _interpreter;
  static bool _metadataLoaded = false;

  static const int _inputSize = 50; // Number of samples required
  static const int _numFeatures = 17;
  static const int _outputSize = 11;
  static const int _smoothingWindow = 5;
  static const double _epsilon = 1e-8;

  static final List<List<double>> _featureBuffer = <List<double>>[];
  static final List<int> _predictionHistory = <int>[];

  static List<String> _activityLabels = List<String>.from(_defaultLabelDisplay);
  static String? _latestPredictionText;
  static double _latestConfidence = 0.0;

  static const List<String> _featureKeys = <String>[
    'accelX',
    'accelY',
    'accelZ',
    'gravityX',
    'gravityY',
    'gravityZ',
    'linAccX',
    'linAccY',
    'linAccZ',
    'accelMag',
    'linAccMag',
    'jerkMag',
    'accelVert',
    'accelHorizMag',
    'stride_variability',
    'movement_consistency',
    'jerk_rms',
  ];

  static const List<double> _featureMean = <double>[
    -0.0207375381141901,
    -0.633249044418335,
    0.02610127627849579,
    -0.02064252644777298,
    -0.6332488059997559,
    0.026249036192893982,
    -9.50118264881894e-05,
    -2.460145935856417e-07,
    -0.00014776120951864868,
    1.0214903354644775,
    0.20727160573005676,
    0.27486854791641235,
    0.984337568283081,
    0.12175355851650238,
    0.08928065001964569,
    -0.009514795616269112,
    0.23995821177959442,
  ];

  static const List<double> _featureScale = <double>[
    0.44066229462623596,
    0.5206595659255981,
    0.5126204490661621,
    0.39387020468711853,
    0.4231494665145874,
    0.48281800746917725,
    0.1884622573852539,
    0.289221853017807,
    0.16374623775482178,
    0.2944871187210083,
    0.3209651708602905,
    0.46730488538742065,
    0.328386127948761,
    0.19642598927021027,
    0.12184872478246689,
    0.3156552314758301,
    0.3424205183982849,
  ];

  static const List<double> _classThresholds = <double>[
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.48,
    0.0,
    0.0,
    0.60,
    0.0,
  ];

  static const List<String> _defaultLabelDisplay = <String>[
    'Ascending stairs',
    'Descending stairs',
    'Lying back',
    'Lying left',
    'Lying right',
    'Lying stomach',
    'Miscellaneous movements',
    'Normal walking',
    'Running',
    'Shuffle walking',
    'Sitting / Standing',
  ];

  static const Map<String, String> _labelDisplayMap = <String, String>{
    'ascending': 'Ascending stairs',
    'descending': 'Descending stairs',
    'lyingBack': 'Lying back',
    'lyingLeft': 'Lying left',
    'lyingRight': 'Lying right',
    'lyingStomach': 'Lying stomach',
    'miscMovement': 'Miscellaneous movements',
    'normalWalking': 'Normal walking',
    'running': 'Running',
    'shuffleWalking': 'Shuffle walking',
    'sittingStanding': 'Sitting / Standing',
  };

  static Future<bool> initialize() async {
    if (_interpreter != null) {
      return true;
    }
    try {
      await _loadMetadata();
      _interpreter = await Interpreter.fromAsset('final_model_float16.tflite');
      print('HAR model loaded successfully');
      return true;
    } catch (e) {
      print('Failed to load HAR model: $e');
      return false;
    }
  }

  static Future<void> _loadMetadata() async {
    if (_metadataLoaded) {
      return;
    }
    try {
      final String jsonString =
          await rootBundle.loadString('HAR_CNN_labels.json');
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is List && decoded.length == _outputSize) {
        _activityLabels = decoded
            .cast<String>()
            .map((label) => _labelDisplayMap[label] ?? label)
            .toList(growable: false);
      } else {
        print(
            'HARService: unexpected label list format, falling back to defaults.');
      }
    } catch (e) {
      print('HARService: unable to load HAR_CNN_labels.json ($e), using defaults.');
      _activityLabels = List<String>.from(_defaultLabelDisplay);
    }
    _metadataLoaded = true;
  }

  static bool addFeatureSample(
    Map<String, double> feature, {
    required bool isStepBoundary,
  }) {
    final List<double> row = _buildFeatureRow(feature);
    _featureBuffer.add(row);
    if (_featureBuffer.length > _inputSize) {
      _featureBuffer.removeAt(0);
    }

    if (!isStepBoundary || _featureBuffer.length < _inputSize) {
      return false;
    }
    if (_interpreter == null) {
      return false;
    }

    _runInference();
    return true;
  }

  static String? getLatestPrediction() => _latestPredictionText;

  static int getBufferSize() => _featureBuffer.length;

  static void clearBuffer() {
    _featureBuffer.clear();
    _predictionHistory.clear();
    _latestPredictionText = null;
    _latestConfidence = 0.0;
  }

  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    clearBuffer();
  }

  static List<double> _buildFeatureRow(Map<String, double> feature) {
    final List<double> row = List<double>.filled(_numFeatures, 0.0);
    for (int i = 0; i < _featureKeys.length; i++) {
      row[i] = feature[_featureKeys[i]] ?? 0.0;
    }
    return row;
  }

  static void _runInference() {
    final List<List<double>> window = _featureBuffer
        .sublist(_featureBuffer.length - _inputSize, _featureBuffer.length);

    final List<List<double>> scaledWindow = List<List<double>>.generate(
      _inputSize,
      (int i) {
        final List<double> scaledRow = List<double>.filled(_numFeatures, 0.0);
        final List<double> sourceRow = window[i];
        for (int j = 0; j < _numFeatures; j++) {
          final double scale =
              _featureScale[j].abs() < _epsilon ? 1.0 : _featureScale[j];
          scaledRow[j] = (sourceRow[j] - _featureMean[j]) / scale;
        }
        return scaledRow;
      },
      growable: false,
    );

    final List<List<List<double>>> input = <List<List<double>>>[scaledWindow];
    final List<List<double>> output =
        List<List<double>>.generate(1, (_) => List<double>.filled(_outputSize, 0));

    try {
      _interpreter!.run(input, output);
    } catch (e) {
      print('HARService: inference error $e');
      return;
    }

    final List<double> probabilities = List<double>.from(output[0]);
    int predictedClass = 0;
    double predictedConf = probabilities[0];

    for (int i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > predictedConf) {
        predictedClass = i;
        predictedConf = probabilities[i];
      }
    }

    int adjustedClass = predictedClass;
    double adjustedConf = predictedConf;

    if (adjustedClass == 9 && adjustedConf < 0.60) {
      adjustedClass = 7;
      adjustedConf = probabilities[7];
    }

    if (adjustedConf < _classThresholds[adjustedClass]) {
      adjustedClass = 6;
      adjustedConf = probabilities[6];
    }

    _predictionHistory.add(adjustedClass);
    if (_predictionHistory.length > _smoothingWindow) {
      _predictionHistory.removeAt(0);
    }

    final int smoothedClass = _medianLabel(_predictionHistory);
    _latestConfidence = probabilities[smoothedClass];
    final String label =
        smoothedClass < _activityLabels.length ? _activityLabels[smoothedClass] : 'Class $smoothedClass';
    _latestPredictionText =
        '$label (${(_latestConfidence * 100).toStringAsFixed(1)}%)';
  }

  static int _medianLabel(List<int> history) {
    final List<int> sorted = List<int>.from(history)..sort();
    return sorted[sorted.length ~/ 2];
  }
}
