// lib/services/departure_message_service.dart
//
// 외출 감지 시 발송할 알림 메시지를 결정하는 서비스.
//
// 우선순위:
//   1. 체크리스트 미체크 항목  → "[항목명] 확인했어?"
//   2. 비 예보               → "우산 챙겼어?"
//   3. 미세먼지 나쁨          → "오늘 미세먼지 심하대. 마스크 쓰는 게 좋아."
//   ∅  해당 없음             → 알림 미발송 (하루 제한 횟수 소비 안 함)
//
// 사용처: geofence_service_wrapper._onDepartureConfirmed()

import 'package:flutter/foundation.dart';
import '../data/prefs_service.dart';
import 'daily_notif_guard.dart';
import 'notification_service.dart';
import 'weather_service.dart';

// ── 내부 데이터 클래스 ─────────────────────────────────────────────────────────

class _NotifContent {
  final String title;
  final String body;
  const _NotifContent({required this.title, required this.body});
}

// ── Service ───────────────────────────────────────────────────────────────────

class DepartureMessageService {
  DepartureMessageService._();

  /// 외출 감지 시 호출. 메시지를 결정하고 알림을 발송한다.
  ///
  /// - 보낼 내용이 없으면 DailyNotifGuard를 소비하지 않고 종료한다.
  /// - DailyNotifGuard 확인 후 발송 (하루 제한 준수).
  static Future<void> composeAndSend() async {
    final content = await _compose();

    if (content == null) {
      // 알려줄 내용 없음 → 하루 발송 횟수를 소비하지 않고 종료
      debugPrint('[DepartureMsg] Nothing to notify — skipping');
      return;
    }

    // DailyNotifGuard: DND 및 하루 1회 제한 확인
    final allowed = await DailyNotifGuard.canNotify();
    if (!allowed) {
      debugPrint('[DepartureMsg] Blocked by DailyNotifGuard');
      return;
    }

    debugPrint('[DepartureMsg] Sending: "${content.title}"');
    await NotificationService().showDepartureAlert(content.title, content.body);
  }

  // ── 우선순위 결정 로직 ────────────────────────────────────────────────────

  static Future<_NotifContent?> _compose() async {
    // 1. 체크리스트 미체크 항목 (우선순위 최상위)
    final checklistResult = await _checklistContent();
    if (checklistResult != null) return checklistResult;

    // 2 & 3. 날씨/공기질 (날씨 기능이 켜져 있고 API 키가 있는 경우)
    final apiKey = await PrefsService.getWeatherApiKey();
    final place  = await PrefsService.getActivePlace();

    if (apiKey.isNotEmpty && place != null) {
      // 2. 비 예보 → 우산
      final rainResult = await _rainContent(place.lat, place.lon, apiKey);
      if (rainResult != null) return rainResult;

      // 3. 미세먼지 나쁨 → 마스크
      final dustResult = await _dustContent(place.lat, place.lon, apiKey);
      if (dustResult != null) return dustResult;
    }

    // 해당 없음
    return null;
  }

  // ── 체크리스트 ─────────────────────────────────────────────────────────────

  /// 미체크 항목이 있으면 첫 번째 항목 기반 메시지를 반환한다.
  /// 세션이 없거나 모두 체크된 경우 null.
  static Future<_NotifContent?> _checklistContent() async {
    final unchecked = await PrefsService.getUncheckedChecklistLabels();
    if (unchecked.isEmpty) return null;

    final label = unchecked.first;
    return _NotifContent(
      title: '$label 확인했어?',
      body: '체크리스트를 한 번 더 확인해봐요.',
    );
  }

  // ── 비 예보 ────────────────────────────────────────────────────────────────

  static Future<_NotifContent?> _rainContent(
    double lat,
    double lon,
    String apiKey,
  ) async {
    final isEnabled = await PrefsService.isWeatherEnabled();
    if (!isEnabled) return null;

    try {
      final data = await WeatherService.fetchWeather(lat, lon, apiKey)
          .timeout(const Duration(seconds: 5));
      if (WeatherService.shouldBringUmbrella(data)) {
        return const _NotifContent(
          title: '우산 챙겼어?',
          body: '비 올 것 같아요.',
        );
      }
    } catch (_) {
      debugPrint('[DepartureMsg] Weather fetch failed — skipping rain check');
    }
    return null;
  }

  // ── 미세먼지 ───────────────────────────────────────────────────────────────

  static Future<_NotifContent?> _dustContent(
    double lat,
    double lon,
    String apiKey,
  ) async {
    final isEnabled = await PrefsService.isDustEnabled();
    if (!isEnabled) return null;

    try {
      final data = await WeatherService.fetchAirPollution(lat, lon, apiKey)
          .timeout(const Duration(seconds: 5));
      if (WeatherService.shouldWearMask(data)) {
        return const _NotifContent(
          title: '오늘 미세먼지 심하대.',
          body: '마스크 쓰는 게 좋아.',
        );
      }
    } catch (_) {
      debugPrint('[DepartureMsg] Air pollution fetch failed — skipping dust check');
    }
    return null;
  }
}
