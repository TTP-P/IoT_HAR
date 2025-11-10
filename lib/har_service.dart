import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

// Service class to handle Human Activity Recognition (HAR) using TensorFlow Lite
class HARService {
  HARService._();

  static Interpreter? _interpreter;
  static bool _metadataLoaded = false;

  static const int _inputSize = 25; // Number of samples required
  static const int _numFeatures = 25;
  static const int _outputSize = 11;
  static const int _medianKernelLarge = 5;
  static const int _medianKernelSmall = 3;
  static const int _probabilityWindow = 5;
  static const double _epsilon = 1e-8;
  static const double _lowConfidenceThreshold = 0.4;

  static final List<List<double>> _featureBuffer = <List<double>>[];
  static final List<int> _rawPredictionHistory = <int>[];
  static final List<int> _confidenceAdjustedHistory = <int>[];
  static final List<List<double>> _probabilityHistory = <List<double>>[];

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
    'jerkVert',
    'jerkHorizMag',
    'jerk_rms',
    'jerk_instability',
    'vert_energy_ratio',
    'horiz_energy_ratio',
    'highfreq_ratio',
    'gait_periodicity',
    'stride_variability',
    'movement_consistency',
    'vert_velocity_signed',
    'vert_velocity_trend',
    'lateral_balance',
  ];

  static const List<double> _featureMean = <double>[
    -0.021668165922164917,
    -0.6572025418281555,
    0.03427287936210632,
    -0.02103836089372635,
    -0.6578264236450195,
    0.0361427366733551,
    -0.0006298051448538899,
    0.0006239209324121475,
    -0.0018698560306802392,
    1.0219208002090454,
    0.24593454599380493,
    0.29173874855041504,
    -0.0002578217536211014,
    0.1820693016052246,
    0.3361179828643799,
    0.16432751715183258,
    0.9315782785415649,
    0.06842168420553207,
    16.487808227539062,
    -0.10400755703449249,
    0.18963348865509033,
    0.9839140772819519,
    19.41428565979004,
    0.0008267218945547938,
    121.81930541992188,
  ];

  static const List<double> _featureScale = <double>[
    0.4349856376647949,
    0.5218822956085205,
    0.49425432085990906,
    0.381322979927063,
    0.4149784445762634,
    0.4564850628376007,
    0.2155025750398636,
    0.3259219825267792,
    0.19245800375938416,
    0.3083796501159668,
    0.35948166251182556,
    0.47981226444244385,
    0.42215633392333984,
    0.3224376440048218,
    0.44908982515335083,
    0.21452125906944275,
    0.17211775481700897,
    0.1721177101135254,
    1302.8140869140625,
    0.3030170500278473,
    0.24368108808994293,
    0.024226132780313492,
    2.092092990875244,
    0.45464491844177246,
    50129.30078125,
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

  static const int _miscIndex = 6;
  static const int _shuffleIndex = 9;
  static const Set<int> _lowConfidenceClasses = <int>{_miscIndex, _shuffleIndex};
  static int? _lastConfidenceAdjustedClass;

  static Future<bool> initialize() async {
    if (_interpreter != null) {
      return true;
    }
    try {
      await _loadMetadata();
      _interpreter = await Interpreter.fromAsset('model/har/final_model_quantized_fp16.tflite');
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
          await rootBundle.loadString('model/har/HAR_CNN_labels.json');
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
    _rawPredictionHistory.clear();
    _confidenceAdjustedHistory.clear();
    _probabilityHistory.clear();
    _lastConfidenceAdjustedClass = null;
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
    final int rawClass = _argmax(probabilities);
    final double rawConfidence = probabilities[rawClass];

    _appendIntWithLimit(_rawPredictionHistory, rawClass, _medianKernelLarge);
    final int step1Class = _medianLabel(_rawPredictionHistory);

    int step2Class = step1Class;
    if (rawConfidence < _lowConfidenceThreshold &&
        _lowConfidenceClasses.contains(step1Class) &&
        _lastConfidenceAdjustedClass != null) {
      step2Class = _lastConfidenceAdjustedClass!;
    }
    _lastConfidenceAdjustedClass = step2Class;

    _appendIntWithLimit(
        _confidenceAdjustedHistory, step2Class, _medianKernelSmall);
    final int step3Class = _medianLabel(_confidenceAdjustedHistory);

    _probabilityHistory.add(probabilities);
    if (_probabilityHistory.length > _probabilityWindow) {
      _probabilityHistory.removeAt(0);
    }
    final List<double> smoothedProbabilities =
        _averageProbabilities(_probabilityHistory);
    final int softClass = _argmax(smoothedProbabilities);

    final int finalClass =
        softClass == _miscIndex ? softClass : step3Class;

    _latestConfidence = smoothedProbabilities[finalClass];
    final String label = finalClass < _activityLabels.length
        ? _activityLabels[finalClass]
        : 'Class $finalClass';
    _latestPredictionText =
        '$label (${(_latestConfidence * 100).toStringAsFixed(1)}%)';
  }

  static int _medianLabel(List<int> history) {
    final List<int> sorted = List<int>.from(history)..sort();
    return sorted[sorted.length ~/ 2];
  }

  static void _appendIntWithLimit(List<int> history, int value, int limit) {
    history.add(value);
    if (history.length > limit) {
      history.removeAt(0);
    }
  }

  static int _argmax(List<double> values) {
    int index = 0;
    double maxValue = values[0];
    for (int i = 1; i < values.length; i++) {
      if (values[i] > maxValue) {
        index = i;
        maxValue = values[i];
      }
    }
    return index;
  }

  static List<double> _averageProbabilities(List<List<double>> history) {
    final List<double> accumulator =
        List<double>.filled(_outputSize, 0.0, growable: false);
    for (final List<double> row in history) {
      for (int i = 0; i < accumulator.length; i++) {
        accumulator[i] += row[i];
      }
    }
    final double divisor = history.length.toDouble();
    for (int i = 0; i < accumulator.length; i++) {
      accumulator[i] /= divisor;
    }
    return accumulator;
  }
}
