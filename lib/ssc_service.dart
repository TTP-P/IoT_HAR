import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

class SscPrediction {
  const SscPrediction({required this.label, required this.confidence});

  final String label;
  final double confidence;
}

class SSCService {
  SSCService._();

  static const int _inputSize = 50;
  static const int _numFeatures = 15;
  static const int _numClasses = 4;
  static const double _epsilon = 1e-6;

  static Interpreter? _interpreter;
  static bool _metadataLoaded = false;
  static List<String> _labels = List<String>.from(_defaultLabels);

  static final List<List<double>> _featureBuffer = <List<double>>[];

  static String? _latestLabel;
  static double _latestConfidence = 0.0;
  static int? _latestClassIndex;

  static const List<String> _featureKeys = <String>[
    'accelX',
    'accelY',
    'accelZ',
    'linAccMag',
    'jerkMag',
    'jerk_rms',
    'burst_density',
    'breathing_stability',
    'rhythm_stability',
    'cough_energy_ratio',
    'dominant_resp_freq',
    'spectral_sharpness',
    'zero_cross_rate',
    'short_energy_ratio',
    'breathing_disruption',
  ];

  static const List<double> _featureMean = <double>[
    -0.068228,
    -0.367472,
    0.065281,
    0.045307,
    0.054171,
    0.064471,
    0.045562,
    0.966542,
    0.969315,
    1.069497,
    0.812611,
    0.150606,
    0.028828,
    1.027096,
    0.000335,
  ];

  static const List<double> _featureScale = <double>[
    0.532015,
    0.449244,
    0.627323,
    0.05601,
    0.07856,
    0.070716,
    0.114517,
    0.045534,
    0.033554,
    0.880069,
    0.588559,
    0.066729,
    0.078888,
    0.551083,
    0.006,
  ];

  static const List<String> _defaultLabels = <String>[
    'breathingNormally',
    'coughing',
    'hyperventilation',
    'other',
  ];

  static Future<void> initialize() async {
    if (_interpreter != null) {
      return;
    }
    await _loadLabels();
    try {
      _interpreter = await Interpreter.fromAsset(
        'model/ssc/final_model_quantized.tflite',
      );
    } catch (e) {
      print('Failed to load SSC model: $e');
    }
  }

  static Future<void> _loadLabels() async {
    if (_metadataLoaded) {
      return;
    }
    try {
      final String raw = await rootBundle.loadString('model/ssc/labels.json');
      final dynamic decoded = jsonDecode(raw);
      if (decoded is List && decoded.length == _numClasses) {
        _labels = decoded.cast<String>().toList(growable: false);
      }
    } catch (_) {
      _labels = List<String>.from(_defaultLabels);
    }
    _metadataLoaded = true;
  }

  static bool addFeatureSample(Map<String, double> feature) {
    final List<double> row = List<double>.filled(_numFeatures, 0.0);
    for (int i = 0; i < _featureKeys.length; i++) {
      row[i] = feature[_featureKeys[i]] ?? 0.0;
    }

    _featureBuffer.add(row);
    if (_featureBuffer.length > _inputSize) {
      _featureBuffer.removeAt(0);
    }

    if (_featureBuffer.length < _inputSize || _interpreter == null) {
      return false;
    }

    _runInference();
    return true;
  }

  static void _runInference() {
    final List<List<double>> recentWindow = _featureBuffer
        .sublist(_featureBuffer.length - _inputSize, _featureBuffer.length);

    final List<List<List<double>>> input =
        List<List<List<double>>>.generate(1, (_) {
      return List<List<double>>.generate(_inputSize, (int i) {
        final List<double> sourceRow = recentWindow[i];
        return List<double>.generate(_numFeatures, (int j) {
          final double scale = _featureScale[j].abs() < _epsilon
              ? 1.0
              : _featureScale[j];
          return (sourceRow[j] - _featureMean[j]) / scale;
        });
      }, growable: false);
    }, growable: false);

    final List<List<double>> output = List<List<double>>.generate(
      1,
      (_) => List<double>.filled(_numClasses, 0.0),
      growable: false,
    );

    try {
      _interpreter!.run(input, output);
    } catch (e) {
      print('SSCService: inference error $e');
      return;
    }

    final List<double> probabilities = List<double>.from(output[0]);
    final int classIndex = _argmax(probabilities);
    _latestConfidence = probabilities[classIndex];
    _latestClassIndex = classIndex;
    _latestLabel = classIndex < _labels.length
        ? _labels[classIndex]
        : 'Class $classIndex';
  }

  static SscPrediction? getLatestPrediction() {
    if (_latestLabel == null) {
      return null;
    }
    return SscPrediction(
      label: _latestLabel!,
      confidence: _latestConfidence,
    );
  }

  static int getBufferSize() => _featureBuffer.length;

  static void clearBuffer() {
    _featureBuffer.clear();
    _latestLabel = null;
    _latestClassIndex = null;
    _latestConfidence = 0.0;
  }

  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    clearBuffer();
  }

  static int _argmax(List<double> values) {
    int index = 0;
    double best = values[0];
    for (int i = 1; i < values.length; i++) {
      if (values[i] > best) {
        index = i;
        best = values[i];
      }
    }
    return index;
  }
}
