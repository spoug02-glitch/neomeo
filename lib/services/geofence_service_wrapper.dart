

// lib/services/geofence_service_wrapper.dart
import 'package:flutter/foundation.dart';
import 'package:geofencing_api/geofencing_api.dart';
import '../data/prefs_service.dart';
import '../data/place.dart';
import 'daily_notif_guard.dart';
import 'notification_service.dart';

// Top-level listener bound by the wrapper
Future<void> _onGeofenceStatusChanged(
  GeofenceRegion region,
  GeofenceStatus status,
  Location location,
) async {
  if (kIsWeb) return;

  if (status == GeofenceStatus.exit) {
    final allowed = await DailyNotifGuard.canNotify();
    if (allowed) {
      await NotificationService().showGeofenceAlert();
    }
  }
}

class GeofenceServiceWrapper {
  static Future<bool> isHomeSet() async {
    // TODO: 실제로는 SharedPreferences 등에서 "집 설정 여부"를 읽어야 함
    return false;
}
  static final GeofenceServiceWrapper _instance = GeofenceServiceWrapper._();
  factory GeofenceServiceWrapper() => _instance;
  GeofenceServiceWrapper._();

  bool _running = false;

  // ── Public API ─────────────────────────────────────────

  Future<void> startMonitoringActivePlace() async {
    final activePlace = await PrefsService.getActivePlace();
    if (activePlace != null) {
      await startMonitoring(activePlace.lat, activePlace.lon, activePlace.id);
    }
  }

  Future<void> startFromSaved() async {
    await startMonitoringActivePlace();
  }

  Future<void> startMonitoring(double lat, double lon, String id) async {
    if (_running) await stopMonitoring();

    Geofencing.instance.setup(
      interval: 5000,
      accuracy: 100,
    );

    Geofencing.instance.addGeofenceStatusChangedListener(_onGeofenceStatusChanged);

    final region = GeofenceCircularRegion(
      id: id,
      center: LatLng(lat, lon),
      radius: 100.0,
    );

    await Geofencing.instance.start(regions: {region});
    _running = true;
  }

  Future<void> stopMonitoring() async {
    if (!_running) return;
    Geofencing.instance.removeGeofenceStatusChangedListener(_onGeofenceStatusChanged);
    await Geofencing.instance.stop();
    _running = false;
  }
}
