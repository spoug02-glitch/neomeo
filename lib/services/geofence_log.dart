// lib/services/geofence_log.dart
//
// 지오펜스 이벤트를 SharedPreferences에 기록.
// 앱 내 설정 화면에서 USB 없이 확인 가능.

import 'package:shared_preferences/shared_preferences.dart';

class GeofenceLog {
  static const _kKey = 'geofence_event_log';
  static const _kMax = 40;

  /// 이벤트 기록 (어느 아이솔레이트에서나 호출 가능)
  static Future<void> add(String event) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kKey) ?? [];
    final now = DateTime.now();
    final ts = '${now.month.toString().padLeft(2,'0')}/'
        '${now.day.toString().padLeft(2,'0')} '
        '${now.hour.toString().padLeft(2,'0')}:'
        '${now.minute.toString().padLeft(2,'0')}:'
        '${now.second.toString().padLeft(2,'0')}';
    list.add('$ts  $event');
    if (list.length > _kMax) list.removeRange(0, list.length - _kMax);
    await prefs.setStringList(_kKey, list);
  }

  /// 최신순으로 반환
  static Future<List<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // 백그라운드 아이솔레이트가 쓴 값을 반영
    return (prefs.getStringList(_kKey) ?? []).reversed.toList();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
