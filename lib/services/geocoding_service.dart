// lib/services/geocoding_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app/app_config.dart';

class GeocodingService {
  static const _baseUrl = 'https://dapi.kakao.com/v2/local/geo';

  /// 위도/경도 → 한국어 주소 (카카오 로컬 API)
  ///
  /// 1차: coord2regioncode → 행정동 이름 (GPS 오차에 강함, 동 단위 정확)
  /// 2차: coord2address   → 지번 주소 address_name (fallback)
  /// 실패 시 null 반환.
  static Future<String?> reverseGeocode(double lat, double lon) async {
    final key = AppConfig.kakaoApiKey;
    if (key.isEmpty || key == 'YOUR_KAKAO_REST_API_KEY_HERE') return null;

    final headers = {'Authorization': 'KakaoAK $key'};

    // ── 1차: 행정동 기반 주소 ─────────────────────────────
    try {
      final uri = Uri.parse(
        '$_baseUrl/coord2regioncode.json?x=$lon&y=$lat',
      );
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final docs = (jsonDecode(res.body)['documents'] as List?) ?? [];
        // region_type H = 행정동, B = 법정동 — H 우선
        final h = docs.firstWhere(
          (d) => d['region_type'] == 'H',
          orElse: () => docs.isNotEmpty ? docs[0] : null,
        );
        if (h != null) {
          final name = h['address_name'] as String?;
          if (name != null && name.isNotEmpty) return name;
        }
      }
    } catch (_) {}

    // ── 2차: 지번 주소 fallback ───────────────────────────
    try {
      final uri = Uri.parse(
        '$_baseUrl/coord2address.json?x=$lon&y=$lat',
      );
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final docs = (jsonDecode(res.body)['documents'] as List?) ?? [];
        if (docs.isNotEmpty) {
          final jibun = docs[0]['address']?['address_name'] as String?;
          if (jibun != null && jibun.isNotEmpty) return jibun;

          final road = docs[0]['road_address']?['address_name'] as String?;
          if (road != null && road.isNotEmpty) return road;
        }
      }
    } catch (_) {}

    return null;
  }
}
