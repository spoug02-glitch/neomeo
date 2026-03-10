// lib/utils/recommendation_service.dart
//
// 설정 상태를 기반으로 오늘의 추천 아이템을 반환한다.
// 실제 API 호출 없이 설정값만 사용하는 mock 로직이다.

import '../data/prefs_service.dart';

class RecommendationService {
  /// 날씨/미세먼지/온도 민감도 설정에 따라 추천 아이템 목록을 반환한다.
  ///
  /// - 날씨 연동 ON  → 우산
  /// - 미세먼지 연동 ON → 마스크
  /// - 온도 민감도 < 5.0 → 겉옷
  static Future<List<String>> getTodayRecommendations() async {
    final weatherEnabled = await PrefsService.isWeatherEnabled();
    final dustEnabled = await PrefsService.isDustEnabled();
    final tempSensitivity = await PrefsService.getTempSensitivity();

    final List<String> recommendations = [];

    if (weatherEnabled) recommendations.add('우산');
    if (dustEnabled) recommendations.add('마스크');
    if (tempSensitivity < 5.0) recommendations.add('겉옷');

    return recommendations;
  }

  static String emojiFor(String item) {
    switch (item) {
      case '우산':
        return '☔';
      case '마스크':
        return '😷';
      case '겉옷':
        return '🧥';
      default:
        return '📦';
    }
  }
}
