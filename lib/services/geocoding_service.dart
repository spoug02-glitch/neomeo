// lib/services/geocoding_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app/app_config.dart';

class GeocodingService {
  static const _baseUrl = 'https://dapi.kakao.com/v2/local/geo';

  /// 위도/경도 → 간결한 한국어 주소 (카카오 로컬 API)
  ///
  /// 도로명 우선: "세종시 다정북로 109" 형태
  /// 지번 대체:   "세종시 다정동 123" 형태
  /// 실패 시 null 반환.
  static Future<String?> reverseGeocode(double lat, double lon) async {
    final key = AppConfig.kakaoApiKey;
    if (key.isEmpty || key == 'YOUR_KAKAO_REST_API_KEY_HERE') return null;

    final headers = {'Authorization': 'KakaoAK $key'};

    // ── 1차: coord2address — 도로명/지번 주소 ─────────────────
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
          // 도로명 주소 — 간결 포맷: 시/군/구 + 도로명 + 번호
          final road = docs[0]['road_address'];
          if (road != null) {
            final short = _buildRoadShort(road);
            if (short != null) return short;
          }

          // 지번 주소 — 간결 포맷: 시/군/구 + 동/리 + 번지
          final jibun = docs[0]['address'];
          if (jibun != null) {
            final short = _buildJibunShort(jibun);
            if (short != null) return short;
          }
        }
      }
    } catch (_) {}

    // ── 2차: 행정동 이름 fallback (coord2regioncode) ──────
    try {
      final uri = Uri.parse(
        '$_baseUrl/coord2regioncode.json?x=$lon&y=$lat',
      );
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final docs = (jsonDecode(res.body)['documents'] as List?) ?? [];
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

    return null;
  }

  /// 도로명 주소 간결 조합: "세종시 다정북로 109"
  static String? _buildRoadShort(Map<String, dynamic> road) {
    final region1 = road['region_1depth_name'] as String? ?? '';
    final region2 = road['region_2depth_name'] as String? ?? '';
    final roadName = road['road_name'] as String? ?? '';
    final mainNo = road['main_building_no'] as String? ?? '';
    final subNo = road['sub_building_no'] as String? ?? '';

    if (roadName.isEmpty || mainNo.isEmpty) {
      // 필드 파싱 실패 시 address_name fallback
      final full = road['address_name'] as String?;
      return (full != null && full.isNotEmpty) ? full : null;
    }

    // 시/도 + 구/군(선택) + 도로명 + 번호
    final parts = <String>[
      if (region1.isNotEmpty) region1,
      if (region2.isNotEmpty) region2,
      roadName,
      subNo.isNotEmpty && subNo != '0' ? '$mainNo-$subNo' : mainNo,
    ];
    return parts.join(' ');
  }

  /// 지번 주소 간결 조합: "세종시 다정동 123"
  static String? _buildJibunShort(Map<String, dynamic> addr) {
    final region1 = addr['region_1depth_name'] as String? ?? '';
    final region2 = addr['region_2depth_name'] as String? ?? '';
    final region3 = addr['region_3depth_name'] as String? ?? '';
    final mainNo = addr['main_address_no'] as String? ?? '';
    final subNo = addr['sub_address_no'] as String? ?? '';

    if (mainNo.isEmpty) {
      final full = addr['address_name'] as String?;
      return (full != null && full.isNotEmpty) ? full : null;
    }

    final parts = <String>[
      if (region1.isNotEmpty) region1,
      if (region2.isNotEmpty) region2,
      if (region3.isNotEmpty) region3,
      subNo.isNotEmpty && subNo != '0' ? '$mainNo-$subNo' : mainNo,
    ];
    return parts.join(' ');
  }
}
