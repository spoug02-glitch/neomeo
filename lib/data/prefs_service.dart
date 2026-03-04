// lib/data/prefs_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'place.dart';

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
    return p.getBool(_kWeatherEnabled) ?? false;
  }

  static Future<void> setWeatherEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWeatherEnabled, enabled);
  }

  static Future<bool> isDustEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kDustEnabled) ?? false;
  }

  static Future<void> setDustEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDustEnabled, enabled);
  }

  static Future<String> getWeatherApiKey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kWeatherApiKey) ?? '';
  }

  static Future<void> setWeatherApiKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWeatherApiKey, key);
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
