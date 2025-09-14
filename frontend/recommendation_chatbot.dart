import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Single place item from API
class PlaceRec {
  final String name;
  final String address;
  final double score;

  PlaceRec({required this.name, required this.address, required this.score});

  factory PlaceRec.fromJson(Map<String, dynamic> json) => PlaceRec(
    name: json['name'] as String? ?? '',
    address: json['address'] as String? ?? '',
    score: (json['score'] as num?)?.toDouble() ?? 0.0,
  );
}

/// Root API response
class RecommendationResponse {
  final String query;
  final List<PlaceRec> results;

  RecommendationResponse({required this.query, required this.results});

  factory RecommendationResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['results'] as List<dynamic>? ?? [])
        .map((e) => PlaceRec.fromJson(e as Map<String, dynamic>))
        .toList();
    return RecommendationResponse(
      query: json['query'] as String? ?? '',
      results: list,
    );
  }
}

class RecommendationApi {
  RecommendationApi._();

  /// Choose base URL per platform
  static String get _baseUrl {
    // Web builds use localhost
    if (kIsWeb) return 'http://127.0.0.1:8000';

    // Android emulator reaches host via 10.0.2.2
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';

    // iOS simulator / desktop
    return 'http://127.0.0.1:8000';

    // NOTE: for a real phone on Wi-Fi, replace with your PC LAN IP:
    // return 'http://192.168.1.10:8000';
  }

  static Uri get _recommendUri => Uri.parse('$_baseUrl/recommend');

  /// POST /recommend { text, top_k }
  static Future<RecommendationResponse> getRecommendations({
    required String text,
    int topK = 5,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final res = await http
        .post(
      _recommendUri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'text': text, 'top_k': topK}),
    )
        .timeout(timeout);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return RecommendationResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    }

    throw HttpException(
      'API ${res.statusCode}: ${res.body.isNotEmpty ? res.body : res.reasonPhrase}',
      uri: _recommendUri,
    );
  }
}
