// lib/services/daily_notif_guard.dart
//
// Enforces the "1 notification per day, 2 if extra allowed" rule.
// State is stored in SharedPreferences for atomic, fast access.
// Date is resolved in Asia/Seoul timezone.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class DailyNotifGuard {
  static const _kDate = 'geofence_date';
  static const _kCount = 'geofence_count';
  static const _kExtra = 'geofence_extra_allowed';

  // Returns today's date string YYYYMMDD in Asia/Seoul.
  static String _todaySeoul() {
    // DateTime.now() is local; on Android the device TZ is Seoul on KR devices.
    // For exact Seoul TZ we shift UTC+9 manually if needed.
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateFormat('yyyyMMdd').format(now);
  }

  /// Call this when a geofence EXIT is detected.
  /// Returns true if a notification should be shown.
  static Future<bool> canNotify() async {
    final prefs = await SharedPreferences.getInstance();

    // Check DND
    final dndEnabled = prefs.getBool('dnd_enabled') ?? false;
    if (dndEnabled) {
      final startStr = prefs.getString('dnd_start') ?? '12:00';
      final endStr = prefs.getString('dnd_end') ?? '13:00';
      
      final now = DateTime.now();
      final startParts = startStr.split(':');
      final endParts = endStr.split(':');
      
      final dndStart = DateTime(now.year, now.month, now.day, int.parse(startParts[0]), int.parse(startParts[1]));
      final dndEnd = DateTime(now.year, now.month, now.day, int.parse(endParts[0]), int.parse(endParts[1]));
      
      if (now.isAfter(dndStart) && now.isBefore(dndEnd)) {
        return false; // Suppress during DND
      }
    }

    final today = _todaySeoul();
    final storedDate = prefs.getString(_kDate) ?? '';
    final extraAllowed = prefs.getBool(_kExtra) ?? false;
    final maxCount = extraAllowed ? 2 : 1;

    // New day → reset
    if (storedDate != today) {
      await prefs.setString(_kDate, today);
      await prefs.setInt(_kCount, 0);
      await prefs.setBool(_kExtra, false);
    }

    final count = prefs.getInt(_kCount) ?? 0;
    if (count < maxCount) {
      await prefs.setInt(_kCount, count + 1);
      return true;
    }
    return false;
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

  /// Called by WorkManager midnight task — resets the daily counter.
  static Future<void> resetForNewDay() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todaySeoul();
    await prefs.setString(_kDate, today);
    await prefs.setInt(_kCount, 0);
    await prefs.setBool(_kExtra, false);
  }
}
