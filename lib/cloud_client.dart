import 'dart:convert';
import 'dart:io';

import 'globals.dart';

class CloudPrediction {
  CloudPrediction({
    required this.harLabel,
    required this.harDisplay,
    required this.harConfidence,
    required this.harBufferSize,
    required this.sscLabel,
    required this.sscConfidence,
  });

  final String? harLabel;
  final String? harDisplay;
  final double? harConfidence;
  final int harBufferSize;
  final String? sscLabel;
  final double? sscConfidence;

  factory CloudPrediction.fromJson(Map<String, dynamic> json) {
    return CloudPrediction(
      harLabel: json['har_label'] as String?,
      harDisplay: json['har_display'] as String?,
      harConfidence: (json['har_confidence'] as num?)?.toDouble(),
      harBufferSize: (json['har_buffer_size'] as num?)?.toInt() ?? 0,
      sscLabel: json['ssc_label'] as String?,
      sscConfidence: (json['ssc_confidence'] as num?)?.toDouble(),
    );
  }
}

Future<CloudPrediction?> requestCloudPrediction(
  List<Map<String, Object?>> samples,
) async {
  if (samples.isEmpty) {
    return null;
  }
  final Uri uri = Uri.parse('$cloudServerBaseUrl/predict');
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, Object?>{'samples': samples}));
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      return null;
    }
    final String body = await response.transform(utf8.decoder).join();
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    return CloudPrediction.fromJson(decoded);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> resetCloudState() async {
  final Uri uri = Uri.parse('$cloudServerBaseUrl/reset');
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write('{}');
    await request.close();
  } catch (_) {
    return;
  } finally {
    client.close(force: true);
  }
}
