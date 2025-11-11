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
  static const int _numFeatures = 19;
  static const int _numClasses = 4;
  static const double _epsilon = 1e-6;
  static const double _tauNon = 0.55;
  static const double _tauOther = 0.45;
  static const int _smoothWindow = 5;

  static Interpreter? _interpreter;
  static bool _metadataLoaded = false;
  static List<String> _labels = List<String>.from(_defaultLabels);

  static final List<List<double>> _featureBuffer = <List<double>>[];
  static final List<int> _predictionHistory = <int>[];

  static String? _latestLabel;
  static double _latestConfidence = 0.0;
  static int? _latestClassIndex;

  static const List<String> _featureKeys = <String>[
    'accelX',
    'accelY',
    'accelZ',
    'accelMag',
    'linAccMag',
    'jerkMag',
    'jerk_rms',
    'breathing_stability',
    'rhythm_stability',
    'burst_density',
    'energy_burst_ratio',
    'breathing_intensity_var',
    'fft_energy',
    'zero_cross_rate',
    'dominant_resp_freq',
    'cough_energy_ratio',
    'breathing_disruption',
    'spectral_sharpness',
    'short_energy_ratio',
  ];

  static const List<double> _featureMean = <double>[
    -0.08374115079641342,
    -0.3860498368740082,
    0.06338915973901749,
    1.0106374025344849,
    0.04170093685388565,
    0.04655652865767479,
    0.05512155964970589,
    0.9715603590011597,
    0.9740087985992432,
    0.03951224684715271,
    1.0593878030776978,
    0.848936140537262,
    0.9964520931243896,
    0.02270447462797165,
    0.6663512587547302,
    1.0388972759246826,
    0.00020785958622582257,
    0.1464998871088028,
    1.018700361251831,
  ];

  static const List<double> _featureScale = <double>[
    0.5173215270042419,
    0.4534896910190582,
    0.6255550980567932,
    0.057191021740436554,
    0.05241154879331589,
    0.07199607789516449,
    0.066088005900383,
    0.03903094306588173,
    0.030964549630880356,
    0.09328233450651169,
    0.8716886639595032,
    0.1532822996377945,
    0.006252311170101166,
    0.06950970739126205,
    0.5617320537567139,
    0.7242363095283508,
    0.004739460069686174,
    0.061410170048475266,
    0.47068580985069275,
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
    final int decidedClass = _twoStageDecision(probabilities);
    _predictionHistory.add(decidedClass);
    if (_predictionHistory.length > _smoothWindow) {
      _predictionHistory.removeAt(0);
    }
    final int classIndex = _mode(_predictionHistory);
    _latestClassIndex = classIndex;
    _latestLabel = classIndex < _labels.length
        ? _labels[classIndex]
        : 'Class $classIndex';
    _latestConfidence = classIndex < probabilities.length
        ? probabilities[classIndex]
        : 0.0;
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
    _predictionHistory.clear();
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

  static int _twoStageDecision(List<double> probabilities) {
    if (_labels.isEmpty) {
      return _argmax(probabilities);
    }
    final int otherIndex = _labels.indexOf('other');
    if (otherIndex == -1) {
      return _argmax(probabilities);
    }
    double bestNonOtherValue = -1.0;
    int bestNonOtherIndex = -1;
    for (int i = 0; i < probabilities.length; i++) {
      if (i == otherIndex) {
        continue;
      }
      final double value = probabilities[i];
      if (value > bestNonOtherValue) {
        bestNonOtherValue = value;
        bestNonOtherIndex = i;
      }
    }
    final double otherProb =
        otherIndex < probabilities.length ? probabilities[otherIndex] : 0.0;
    if (bestNonOtherIndex == -1) {
      return otherIndex;
    }
    final bool lowConfidence = bestNonOtherValue < _tauNon;
    final bool otherDominates = otherProb > _tauOther;
    if (lowConfidence && otherDominates) {
      return otherIndex;
    }
    return bestNonOtherIndex;
  }

  static int _mode(List<int> values) {
    if (values.isEmpty) {
      return 0;
    }
    final Map<int, int> counts = <int, int>{};
    for (final int value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    int bestValue = values.last;
    int bestCount = -1;
    counts.forEach((int key, int value) {
      if (value > bestCount || (value == bestCount && key == values.last)) {
        bestValue = key;
        bestCount = value;
      }
    });
    return bestValue;
  }
}
