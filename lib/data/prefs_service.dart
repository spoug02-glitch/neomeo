// lib/data/prefs_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'place.dart';
import '../app/app_config.dart';

class PrefsService {
  static const _kPrepTime = 'prep_time';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kPlaces = 'places_list';
  static const _kActivePlaceId = 'active_place_id';
  static const _kDndEnabled = 'dnd_enabled';
  static const _kDndStart = 'dnd_start'; // HH:mm
  static const _kDndEnd = 'dnd_end';     // HH:mm
  static const _kWeatherEnabled = 'weather_enabled';
  static const _kDustEnabled = 'dust_enabled';
  static const _kWeatherApiKey = 'weather_api_key';
  static const _kTempSensitivity = 'temp_sensitivity';

  static Future<String?> getPrepTime() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPrepTime);
  }

  static Future<void> setPrepTime(String hhmm) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrepTime, hhmm);
  }

  static Future<bool> isOnboardingDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOnboardingDone) ?? false;
  }

  static Future<void> markOnboardingDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboardingDone, true);
  }

  // ── Places Management ──────────────────────────────────

  static Future<List<Place>> getPlaces() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kPlaces) ?? [];
    return list.map((s) => Place.fromJson(jsonDecode(s))).toList();
  }

  static Future<void> savePlaces(List<Place> places) async {
    final p = await SharedPreferences.getInstance();
    final list = places.map((pl) => jsonEncode(pl.toJson())).toList();
    await p.setStringList(_kPlaces, list);
  }

  static Future<String?> getActivePlaceId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kActivePlaceId);
  }

  static Future<void> setActivePlaceId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActivePlaceId, id);
  }

  static Future<Place?> getActivePlace() async {
    final places = await getPlaces();
    final activeId = await getActivePlaceId();
    if (activeId == null || places.isEmpty) return null;
    try {
      return places.firstWhere((pl) => pl.id == activeId);
    } catch (_) {
      return null;
    }
  }

  // ── DND Settings ───────────────────────────────────────

  static Future<bool> isDndEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kDndEnabled) ?? false;
  }

  static Future<void> setDndEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDndEnabled, enabled);
  }

  static Future<String> getDndStart() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDndStart) ?? '12:00';
  }

  static Future<void> setDndStart(String hhmm) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDndStart, hhmm);
  }

  static Future<String> getDndEnd() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDndEnd) ?? '13:00';
  }

  static Future<void> setDndEnd(String hhmm) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDndEnd, hhmm);
  }

  // ── Weather/Dust Settings ──────────────────────────────

  static Future<bool> isWeatherEnabled() async {
    final p = await SharedPreferences.getInstance();
    // API 키가 번들되어 있으면 기본값 true
    final defaultOn = AppConfig.weatherApiKey.isNotEmpty &&
        AppConfig.weatherApiKey != 'YOUR_OWM_API_KEY_HERE';
    return p.getBool(_kWeatherEnabled) ?? defaultOn;
  }

  static Future<void> setWeatherEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWeatherEnabled, enabled);
  }

  static Future<bool> isDustEnabled() async {
    final p = await SharedPreferences.getInstance();
    final defaultOn = AppConfig.weatherApiKey.isNotEmpty &&
        AppConfig.weatherApiKey != 'YOUR_OWM_API_KEY_HERE';
    return p.getBool(_kDustEnabled) ?? defaultOn;
  }

  static Future<void> setDustEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDustEnabled, enabled);
  }

  static Future<String> getWeatherApiKey() async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString(_kWeatherApiKey) ?? '';
    // 저장된 키가 없으면 앱 번들 키를 사용한다
    return stored.isNotEmpty ? stored : AppConfig.weatherApiKey;
  }

  static Future<void> setWeatherApiKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWeatherApiKey, key);
  }

  // ── Checklist Session ──────────────────────────────────
  // 체크리스트 상태를 저장해 외출 감지 시 미체크 항목을 알림에 활용한다.
  // 형식: [{"label": "가스불", "checked": false}, ...]

  static const _kChecklistSession = 'checklist_session';

  /// 체크리스트 상태를 저장한다.
  /// [items] 는 각 항목의 label(String)과 checked(bool) 필드를 포함한 Map 리스트.
  static Future<void> saveChecklistSession(
      List<Map<String, dynamic>> items) async {
    final p = await SharedPreferences.getInstance();
    final encoded = items.map((m) => jsonEncode(m)).toList();
    await p.setStringList(_kChecklistSession, encoded);
  }

  /// 저장된 체크리스트 세션 전체를 반환한다 (label + checked).
  /// 세션이 없으면 빈 리스트를 반환한다.
  static Future<List<Map<String, dynamic>>> getChecklistSession() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kChecklistSession) ?? [];
    return raw.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  /// 저장된 세션에서 체크되지 않은 항목의 label 리스트를 반환한다.
  /// 세션이 없으면 빈 리스트를 반환한다.
  static Future<List<String>> getUncheckedChecklistLabels() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kChecklistSession) ?? [];
    final result = <String>[];
    for (final s in raw) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (!(m['checked'] as bool? ?? false)) {
        result.add(m['label'] as String);
      }
    }
    return result;
  }

  /// 체크리스트 세션을 초기화한다 (새 외출 세션 시작 시 호출).
  static Future<void> clearChecklistSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kChecklistSession);
  }

  static Future<double> getTempSensitivity() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_kTempSensitivity) ?? 0.0;
  }

  static Future<void> setTempSensitivity(double value) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kTempSensitivity, value);
  }
}
