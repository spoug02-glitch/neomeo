// lib/services/daily_notif_guard.dart
//
// Enforces the "1 notification per day, 2 if extra allowed" rule.
// State is stored in SharedPreferences for atomic, fast access.
// Date is resolved in Asia/Seoul timezone.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class DailyNotifGuard {
  static const _kDate        = 'geofence_date';
  static const _kCount       = 'geofence_count';
  static const _kExtra       = 'geofence_extra_allowed';
  static const _kLastNotifAt = 'last_notif_at_ms';

  /// 알람 발송 후 재발송까지 최소 대기 시간 (3시간)
  static const _kCooldownMs = 3 * 60 * 60 * 1000;

  // Returns today's date string YYYYMMDD in Asia/Seoul.
  static String _todaySeoul() {
    // DateTime.now() is local; on Android the device TZ is Seoul on KR devices.
    // For exact Seoul TZ we shift UTC+9 manually if needed.
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateFormat('yyyyMMdd').format(now);
  }

  /// Call this when a geofence EXIT is detected.
  /// Returns true if a notification should be shown.
  ///
  /// 정책: 쿨다운 방식 (하루 N회 제한 없음)
  ///   - 기본: 마지막 알림 후 3시간 이내면 차단
  ///   - '다시 알림 받기' ON: 쿨다운 면제 (1회 소진 후 자동 해제)
  ///   - DND 시간대: 항상 차단
  static Future<bool> canNotify() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. DND 체크
    final dndEnabled = prefs.getBool('dnd_enabled') ?? false;
    if (dndEnabled) {
      final startStr = prefs.getString('dnd_start') ?? '12:00';
      final endStr   = prefs.getString('dnd_end')   ?? '13:00';
      final now = DateTime.now();
      final sp = startStr.split(':');
      final ep = endStr.split(':');
      final dndStart = DateTime(now.year, now.month, now.day,
          int.parse(sp[0]), int.parse(sp[1]));
      final dndEnd = DateTime(now.year, now.month, now.day,
          int.parse(ep[0]), int.parse(ep[1]));
      if (now.isAfter(dndStart) && now.isBefore(dndEnd)) {
        debugPrint('[DailyNotifGuard] Blocked: DND active');
        return false;
      }
    }

    // 2. 쿨다운 체크
    final extraAllowed = prefs.getBool(_kExtra) ?? false;
    final lastNotifAt  = prefs.getInt(_kLastNotifAt) ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (!extraAllowed && (nowMs - lastNotifAt) < _kCooldownMs) {
      final minLeft = (_kCooldownMs - (nowMs - lastNotifAt)) ~/ 60000;
      debugPrint('[DailyNotifGuard] Blocked: cooldown ${minLeft}m remaining');
      return false;
    }

    // 3. 발송 허용 — 상태 업데이트
    await prefs.setInt(_kLastNotifAt, nowMs);
    await prefs.setBool(_kExtra, false); // extra 1회 소진
    debugPrint('[DailyNotifGuard] Allowed (extraWas=$extraAllowed)');
    return true;
  }

  /// Toggle "다시 알림 받기" — allows one extra notification today (up to 2 total).
  static Future<void> allowExtraToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kExtra, true);
  }

  /// Cancel the extra allowance.
  static Future<void> disallowExtra() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kExtra, false);
  }

  /// Read current toggle state.
  static Future<bool> isExtraAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kExtra) ?? false;
  }

  /// 쿨다운 즉시 초기화 (테스트용 — 다음 외출 감지 시 즉시 알림 발송 가능)
  static Future<void> resetCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastNotifAt, 0);
    await prefs.setBool(_kExtra, false);
    debugPrint('[DailyNotifGuard] Cooldown reset manually');
  }

  /// Called by WorkManager midnight task — resets the daily counter.
  static Future<void> resetForNewDay() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todaySeoul();
    await prefs.setString(_kDate, today);
    await prefs.setInt(_kCount, 0);
    await prefs.setBool(_kExtra, false);
  }
}
