// lib/services/geofence_service_wrapper.dart
//
// ══ 모드별 동작 ══════════════════════════════════════════════════════════════
//
//  [DEBUG]
//    GeofenceTaskHandler.onRepeatEvent() — 10초마다 fl_location으로 위치 폴링
//    → 거리 직접 계산 → 상태 머신 (SharedPreferences)
//    로그 태그: [GeoTask-D]
//
//  [RELEASE]
//    GeofenceTaskHandler.onStart() — geofencing_api를 TaskHandler 아이솔레이트에서 시작
//    → geofencing_api 이벤트 드리븐 (exit/enter 콜백)
//    → 기존 geofencing_api를 메인 아이솔레이트에서 쓰면 앱 백그라운드 시 아이솔레이트 정지로 이벤트 누락됨
//    → TaskHandler 아이솔레이트는 포그라운드 서비스와 함께 항상 살아있어 이 문제 없음
//    로그 태그: [GeoTask-R]
//
// ══ 공통 동작 ════════════════════════════════════════════════════════════════
//  - 80m 이탈 감지 → 30초 대기 → 외출 확정 → 알림 발송
//  - 60m 이내 복귀 → atHome 리셋 (hysteresis)
//  - 기기 재부팅 후 자동 재시작 (autoRunOnBoot: true)

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:fl_location/fl_location.dart';
import 'package:geofencing_api/geofencing_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/prefs_service.dart';
import 'departure_message_service.dart';
import 'notification_service.dart';
import 'geofence_log.dart';

// ── 공통 상수 ─────────────────────────────────────────────────────────────────

const _kDepartureRadius = 80.0;                   // m: 이탈 감지 반경
const _kResetRadius     = 60.0;                   // m: 귀가 리셋 반경 (hysteresis)
const _kConfirmDelay    = Duration(seconds: 30);  // 이탈 확정 대기 시간
const _kMaxAccuracyM    = 150.0;                  // m: GPS 정확도 허용 오차
const _kStartupGrace    = Duration(seconds: 15);  // 시작 직후 이탈 무시 구간

// geofencing_api 지오펜스 ID 접미사 (release 모드)
const _kOuterSuffix = ':outer'; // 80m 외곽
const _kInnerSuffix = ':inner'; // 60m 내부

// SharedPreferences 키 (debug 모드 TaskHandler 상태)
const _kStateKey       = 'geofence_task_state';       // 'atHome' | 'pending' | 'notified'
const _kPendingSinceMs = 'geofence_pending_since_ms'; // pending 시작 시각 (epoch ms)

// ── [RELEASE] 모듈 레벨 상태 머신 ─────────────────────────────────────────────
// TaskHandler 아이솔레이트에서 geofencing_api 콜백과 공유

enum _DepState { atHome, pending, notified }

_DepState _state = _DepState.atHome;
Timer? _confirmTimer;
DateTime? _geoStartedAt;

// ── [RELEASE] geofencing_api 콜백 (TaskHandler 아이솔레이트에서 실행) ───────────

Future<void> _onGeofenceStatusChanged(
  GeofenceRegion region,
  GeofenceStatus status,
  Location location,
) async {
  final msg = '[R] ${region.id.split(':').last} $status '
      'acc=${location.accuracy.toStringAsFixed(0)}m state=$_state';
  debugPrint('[GeoTask-R] $msg');
  await GeofenceLog.add(msg);

  // 시작 직후 grace period — 이미 밖에 있을 때 false-positive 방지
  final inGrace = _geoStartedAt != null &&
      DateTime.now().difference(_geoStartedAt!) < _kStartupGrace;

  final id = region.id;
  if (id.endsWith(_kOuterSuffix) && status == GeofenceStatus.exit) {
    if (!inGrace) {
      _handleDepartureCandidate();
    } else {
      debugPrint('[GeoTask-R] exit ignored (startup grace)');
      await GeofenceLog.add('[R] exit ignored (startup grace)');
    }
  } else if (id.endsWith(_kInnerSuffix) && status == GeofenceStatus.enter) {
    _handleReturnHome();
  }
}

void _handleDepartureCandidate() {
  if (_state != _DepState.atHome) {
    GeofenceLog.add('[R] exit ignored (state=$_state)');
    return;
  }
  GeofenceLog.add('[R] → PENDING (${_kConfirmDelay.inSeconds}s 타이머 시작)');
  debugPrint('[GeoTask-R] → pending (${_kConfirmDelay.inSeconds}s 타이머 시작)');
  _state = _DepState.pending;
  _confirmTimer?.cancel();
  _confirmTimer = Timer(_kConfirmDelay, _onDepartureConfirmed);
}

Future<void> _onDepartureConfirmed() async {
  if (_state != _DepState.pending) return;
  _state = _DepState.notified;
  debugPrint('[GeoTask-R] → 외출 확정! 알림 발송');
  await GeofenceLog.add('[R] → NOTIFIED 알림 발송');
  await DepartureMessageService.composeAndSend();
  await PrefsService.clearChecklistSession();
}

void _handleReturnHome() {
  final was = _state;
  _confirmTimer?.cancel();
  _confirmTimer = null;
  _state = _DepState.atHome;
  debugPrint('[GeoTask-R] → atHome (was=$was)');
  GeofenceLog.add('[R] → atHome (was=$was)');
  _checkAndSendArrivalNotif(); // fire-and-forget
}

Future<void> _checkAndSendArrivalNotif() async {
  final place = await PrefsService.getActivePlace();
  if (place == null) return;
  final trigger = await PrefsService.getChecklistTrigger(place.id);
  if (trigger == 'enter') {
    await NotificationService().showArrivalPrompt();
    await GeofenceLog.add('[R] → 귀가 알림 발송 (trigger=enter)');
  }
}

// ── 포그라운드 서비스 진입점 (top-level 필수) ─────────────────────────────────

@pragma('vm:entry-point')
void startGeofenceTask() {
  FlutterForegroundTask.setTaskHandler(GeofenceTaskHandler());
}

// ── TaskHandler ───────────────────────────────────────────────────────────────

class GeofenceTaskHandler extends TaskHandler {
  int? _startedAtMs; // debug 모드 grace period용

  // ── onStart ────────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _startedAtMs = timestamp.millisecondsSinceEpoch;
    // 이 아이솔레이트에서도 알림 플러그인 초기화
    await NotificationService().init();

    if (kReleaseMode) {
      await GeofenceLog.add('[R] TaskHandler 시작 (release geofencing_api)');
      await _startReleaseGeofencing();
    } else {
      debugPrint('[GeoTask-D] TaskHandler started (10s polling mode)');
      await GeofenceLog.add('[D] TaskHandler 시작 (debug 10s polling)');
    }
  }

  /// [RELEASE] geofencing_api 시작 — TaskHandler 아이솔레이트에서 호출
  Future<void> _startReleaseGeofencing() async {
    final place = await PrefsService.getActivePlace();
    if (place == null) {
      debugPrint('[GeoTask-R] onStart: no active place, geofencing not started');
      return;
    }

    _geoStartedAt = DateTime.now();
    _state = _DepState.atHome;

    try {
      Geofencing.instance.setup(
        interval: 10000, // 위치 폴링 주기 10초
        accuracy: _kMaxAccuracyM.toInt(),
      );
      Geofencing.instance.addGeofenceStatusChangedListener(_onGeofenceStatusChanged);

      final outer = GeofenceCircularRegion(
        id: '${place.id}$_kOuterSuffix',
        center: LatLng(place.lat, place.lon),
        radius: _kDepartureRadius,
      );
      final inner = GeofenceCircularRegion(
        id: '${place.id}$_kInnerSuffix',
        center: LatLng(place.lat, place.lon),
        radius: _kResetRadius,
      );

      await Geofencing.instance.start(regions: {outer, inner});
      debugPrint('[GeoTask-R] geofencing_api started — '
          'lat=${place.lat} lon=${place.lon} '
          'outer=${_kDepartureRadius}m inner=${_kResetRadius}m');
      await GeofenceLog.add('[R] geofencing_api 시작 완료 '
          'outer=${_kDepartureRadius}m inner=${_kResetRadius}m');
    } catch (e) {
      debugPrint('[GeoTask-R] geofencing_api start failed: $e');
      await GeofenceLog.add('[R] geofencing_api 시작 실패: $e');
    }
  }

  // ── onRepeatEvent ──────────────────────────────────────────────────────────

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Release 모드: geofencing_api가 이벤트 드리븐으로 처리 → 폴링 불필요
    if (kReleaseMode) return;

    // Debug 모드: 10초마다 위치 직접 폴링
    final nowMs = timestamp.millisecondsSinceEpoch;

    // startup grace period
    if (_startedAtMs != null &&
        (nowMs - _startedAtMs!) < _kStartupGrace.inMilliseconds) {
      debugPrint('[GeoTask-D] grace period, skipping');
      return;
    }

    final place = await PrefsService.getActivePlace();
    if (place == null) return;

    Location loc;
    try {
      loc = await FlLocation.getLocation(accuracy: LocationAccuracy.balanced)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[GeoTask-D] location fetch failed: $e');
      return;
    }

    if (loc.accuracy > _kMaxAccuracyM) {
      debugPrint('[GeoTask-D] GPS too inaccurate (${loc.accuracy.toStringAsFixed(0)}m), skipping');
      return;
    }

    final dist = _haversineMeters(loc.latitude, loc.longitude, place.lat, place.lon);
    final prefs = await SharedPreferences.getInstance();
    final state = prefs.getString(_kStateKey) ?? 'atHome';

    final distStr = dist.toStringAsFixed(0);
    final accStr = loc.accuracy.toStringAsFixed(0);
    debugPrint('[GeoTask-D] dist=${distStr}m state=$state acc=${accStr}m');
    // 10초마다 기록하면 너무 많아지므로 상태 변화 시에만 로그 기록

    if (dist > _kDepartureRadius) {
      if (state == 'atHome') {
        await prefs.setString(_kStateKey, 'pending');
        await prefs.setInt(_kPendingSinceMs, nowMs);
        debugPrint('[GeoTask-D] → pending (${_kConfirmDelay.inSeconds}s 타이머 시작)');
        await GeofenceLog.add('[D] → PENDING dist=${distStr}m acc=${accStr}m');
      } else if (state == 'pending') {
        final since = prefs.getInt(_kPendingSinceMs) ?? nowMs;
        final elapsed = nowMs - since;
        debugPrint('[GeoTask-D] pending ${elapsed ~/ 1000}s / ${_kConfirmDelay.inSeconds}s');
        if (elapsed >= _kConfirmDelay.inMilliseconds) {
          await prefs.setString(_kStateKey, 'notified');
          debugPrint('[GeoTask-D] → 외출 확정! 알림 발송');
          await GeofenceLog.add('[D] → NOTIFIED 알림 발송 dist=${distStr}m');
          await DepartureMessageService.composeAndSend();
          await PrefsService.clearChecklistSession();
        }
      }
      // notified: 귀가 때까지 대기
    } else if (dist <= _kResetRadius) {
      if (state != 'atHome') {
        await prefs.setString(_kStateKey, 'atHome');
        await prefs.remove(_kPendingSinceMs);
        debugPrint('[GeoTask-D] → atHome (귀가 확인)');
        await GeofenceLog.add('[D] → atHome dist=${distStr}m');
        // 귀가 알림 (enter trigger 설정 시)
        final place = await PrefsService.getActivePlace();
        if (place != null) {
          final trigger = await PrefsService.getChecklistTrigger(place.id);
          if (trigger == 'enter') {
            await NotificationService().showArrivalPrompt();
            await GeofenceLog.add('[D] → 귀가 알림 발송 (trigger=enter)');
          }
        }
      }
    }
    // 60~80m: hysteresis zone
  }

  // ── onDestroy ──────────────────────────────────────────────────────────────

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    if (kReleaseMode) {
      // Release: geofencing_api 정리
      try {
        _confirmTimer?.cancel();
        _confirmTimer = null;
        _state = _DepState.atHome;
        Geofencing.instance
            .removeGeofenceStatusChangedListener(_onGeofenceStatusChanged);
        await Geofencing.instance.stop();
        debugPrint('[GeoTask-R] geofencing_api stopped');
      } catch (e) {
        debugPrint('[GeoTask-R] geofencing_api stop failed: $e');
      }
    }
    // Debug: SharedPreferences 상태 초기화
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStateKey, 'atHome');
    await prefs.remove(_kPendingSinceMs);
    debugPrint('[GeoTask] Destroyed');
  }

  // ── 하버사인 거리 공식 (debug 모드 폴링용) ──────────────────────────────────

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dPhi = (lat2 - lat1) * pi / 180;
    final dLambda = (lon2 - lon1) * pi / 180;
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

// ── GeofenceServiceWrapper ────────────────────────────────────────────────────

class GeofenceServiceWrapper {
  static final GeofenceServiceWrapper _instance = GeofenceServiceWrapper._();
  factory GeofenceServiceWrapper() => _instance;
  GeofenceServiceWrapper._();

  bool _running = false;

  static Future<bool> isHomeSet() async {
    final place = await PrefsService.getActivePlace();
    return place != null;
  }

  Future<void> startFromSaved() async => startMonitoringActivePlace();

  Future<void> startMonitoringActivePlace() async {
    final place = await PrefsService.getActivePlace();
    if (place == null) {
      debugPrint('[Geofence] No active place — monitoring not started');
      return;
    }
    await startMonitoring(place.lat, place.lon, place.id);
  }

  /// flutter_foreground_task 초기화 — 앱 시작 시 한 번 호출
  static void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'geofence_fg_channel',
        channelName: '너머 위치 모니터링',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Debug: 10초마다 onRepeatEvent → 위치 폴링
        // Release: nothing() — geofencing_api 이벤트 드리븐 (onRepeatEvent 불필요)
        eventAction: kDebugMode
            ? ForegroundTaskEventAction.repeat(10000) // 10초 (ms)
            : ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true, // 재부팅 후 자동 재시작
      ),
    );
  }

  /// 모니터링 시작 — 포그라운드 서비스 시작만 담당
  /// geofencing_api 초기화는 TaskHandler.onStart()에서 처리 (release 모드)
  Future<void> startMonitoring(double lat, double lon, String placeId) async {
    if (_running) await stopMonitoring();

    // SharedPreferences 상태 초기화
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStateKey, 'atHome');
    await prefs.remove(_kPendingSinceMs);

    if (kIsWeb) return;

    try {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: '너머',
        notificationText: '위치를 확인하고 있어요',
        callback: startGeofenceTask,
      );
      _running = true;
    } catch (e) {
      debugPrint('[Geofence] startService 실패: $e');
      return;
    }

    debugPrint('[Geofence] 포그라운드 서비스 시작 — '
        'mode=${kDebugMode ? "debug(polling)" : "release(geofencing_api)"} '
        'lat=$lat lon=$lon outer=${_kDepartureRadius}m inner=${_kResetRadius}m');
  }

  Future<void> stopMonitoring() async {
    if (!_running) return;
    // TaskHandler.onDestroy()에서 geofencing_api 정리됨
    if (!kIsWeb) await FlutterForegroundTask.stopService();
    _running = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStateKey, 'atHome');
    await prefs.remove(_kPendingSinceMs);

    debugPrint('[Geofence] 모니터링 중지');
  }

  bool get isRunning => _running;
}
