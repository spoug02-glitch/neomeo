// lib/services/geofence_service_wrapper.dart
//
// 집 이탈 감지 로직 — 상태 머신 + hysteresis + 30초 확인 타이머
//
// 동작 흐름:
//   1. 100m 외곽 지오펜스 exit  → pending 상태로 전환, 30초 타이머 시작
//   2. 30초 유지 확인           → DailyNotifGuard 확인 후 알림 발송
//   3. 80m 내부 지오펜스 enter  → 상태 atHome으로 리셋 (다음 외출 준비)
//
// Hysteresis:
//   - 밖으로 나갈 때: 100m 기준 (exit 트리거)
//   - 집으로 돌아올 때: 80m 기준 (enter 리셋)
//   → GPS 흔들림으로 100m 경계를 오가는 false-positive 방지
//
// GPS 튐 방지:
//   - 100m exit 후 30초 이내 80m enter가 오면 타이머 취소 → 알림 미발송
//   - 앱 시작 직후 10초간 exit 이벤트 무시 (재시작 false-positive 방지)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geofencing_api/geofencing_api.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../data/prefs_service.dart';
import 'departure_message_service.dart';

// ── 상수 ──────────────────────────────────────────────────────────────────────

const _kDepartureRadius = 120.0;               // m: 이탈 후보 기준 (UT MVP: 120m)
const _kResetRadius     = 80.0;                // m: 귀가 리셋 기준
const _kConfirmDelay    = Duration(seconds: 30); // GPS 튐 방지 확인 시간
const _kIntervalMs      = 10000;               // 위치 폴링 주기 (10 s)
const _kAccuracyM       = 100;                 // 위치 정확도 허용 오차 (m) — 도심 GPS 오차 감안
const _kStartupGrace    = Duration(seconds: 10); // 시작 직후 exit 무시 구간

const _kOuterSuffix = ':outer'; // 100m 외곽 지오펜스 ID 접미사
const _kInnerSuffix = ':inner'; // 80m 내부 지오펜스 ID 접미사

// ── 상태 머신 (모듈 레벨 — 싱글턴 콜백에서 공유) ─────────────────────────────

enum _DepartureState {
  atHome,   // 집 안(80m 이내) 또는 초기 상태
  pending,  // 100m 밖으로 나감, 30초 타이머 진행 중
  notified, // 오늘 이번 외출 알림 발송 완료. 귀가 시 atHome으로 리셋
}

_DepartureState _state = _DepartureState.atHome;
Timer? _confirmTimer;
DateTime? _monitoringStartedAt; // 시작 시각 (startup grace period용)

// ── 최상위 콜백 (geofencing_api 요구 사항: top-level or static) ───────────────

Future<void> _onGeofenceStatusChanged(
  GeofenceRegion region,
  GeofenceStatus status,
  Location location,
) async {
  if (kIsWeb) return;

  debugPrint('[Geofence] ${region.id} → $status '
      '(state=$_state, dist≈${location.accuracy.toStringAsFixed(0)}m acc)');

  // 앱 재시작 직후 startup grace period: exit 이벤트 무시
  // (이미 밖에 있는 상태에서 앱을 켤 때 false-positive 방지)
  final inGrace = _monitoringStartedAt != null &&
      DateTime.now().difference(_monitoringStartedAt!) < _kStartupGrace;

  final id = region.id;

  if (id.endsWith(_kOuterSuffix) && status == GeofenceStatus.exit) {
    if (!inGrace) _handleDepartureCandidate();
  } else if (id.endsWith(_kInnerSuffix) && status == GeofenceStatus.enter) {
    _handleReturnHome();
  }
}

// ── 상태 전이 핸들러 ──────────────────────────────────────────────────────────

/// 100m 외곽 exit — pending 전환 + 30초 타이머 시작
void _handleDepartureCandidate() {
  if (_state != _DepartureState.atHome) {
    // 이미 pending 또는 notified → 무시 (중복 트리거 방지)
    debugPrint('[Geofence] Departure candidate ignored (state=$_state)');
    return;
  }

  debugPrint('[Geofence] Departure candidate — starting ${_kConfirmDelay.inSeconds}s timer');
  _state = _DepartureState.pending;

  _confirmTimer?.cancel();
  _confirmTimer = Timer(_kConfirmDelay, _onDepartureConfirmed);
}

/// 30초 후 타이머 완료 — 실제 외출로 확정, 알림 발송 + 체크리스트 리셋
Future<void> _onDepartureConfirmed() async {
  if (_state != _DepartureState.pending) return;

  // 알림 전 상태를 notified로 먼저 변경 → 콜백 재진입 방지
  _state = _DepartureState.notified;
  debugPrint('[Geofence] Departure confirmed — composing notification');

  // 1. 메시지 결정 + DailyNotifGuard 확인 + 발송
  //    알려줄 내용이 없으면 DailyNotifGuard를 소비하지 않고 종료
  await DepartureMessageService.composeAndSend();

  // 2. 외출 확정 후 체크리스트 세션 초기화
  //    - 다음 외출(또는 귀가 후)을 위해 체크 상태를 비운다
  //    - 날씨 기반 자동 항목(우산, 마스크)도 함께 초기화됨
  await PrefsService.clearChecklistSession();
  debugPrint('[Geofence] Checklist session cleared after departure');
}

/// 80m 내부 enter — 귀가 확정, 다음 외출을 위해 상태 리셋
void _handleReturnHome() {
  final wasState = _state;
  _confirmTimer?.cancel();
  _confirmTimer = null;
  _state = _DepartureState.atHome;
  debugPrint('[Geofence] User returned home (was=$wasState) — state reset');
}

// ── GeofenceServiceWrapper ────────────────────────────────────────────────────

class GeofenceServiceWrapper {
  static final GeofenceServiceWrapper _instance = GeofenceServiceWrapper._();
  factory GeofenceServiceWrapper() => _instance;
  GeofenceServiceWrapper._();

  bool _running = false;

  /// 온보딩에서 집 위치가 저장되어 있는지 확인
  static Future<bool> isHomeSet() async {
    final place = await PrefsService.getActivePlace();
    return place != null;
  }

  /// 앱 시작 시: 저장된 활성 장소로 모니터링 재개
  Future<void> startFromSaved() async {
    await startMonitoringActivePlace();
  }

  /// 온보딩 완료 후 호출: 방금 저장된 장소로 모니터링 시작
  Future<void> startMonitoringActivePlace() async {
    final place = await PrefsService.getActivePlace();
    if (place == null) {
      debugPrint('[Geofence] No active place found — monitoring not started');
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
      foregroundTaskOptions: const ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
      ),
    );
  }

  /// 직접 좌표를 지정해 모니터링 시작 (테스트 / 장소 변경 시 사용)
  Future<void> startMonitoring(double lat, double lon, String placeId) async {
    if (_running) await stopMonitoring();

    // 상태 머신 초기화
    _state = _DepartureState.atHome;
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _monitoringStartedAt = DateTime.now();

    try {
      // geofencing_api v2.0.0은 fl_location의 getLocationStream()을 사용하는
      // 순수 Dart 구현이다. 포그라운드 서비스 알림은 fl_location이 자동으로
      // 관리하며, 별도 notificationOptions 설정이 필요 없다.
      Geofencing.instance.setup(
        interval: _kIntervalMs,
        accuracy: _kAccuracyM,
      );

      Geofencing.instance
          .addGeofenceStatusChangedListener(_onGeofenceStatusChanged);

      // 외곽 지오펜스: exit → 이탈 후보
      final outerRegion = GeofenceCircularRegion(
        id: '$placeId$_kOuterSuffix',
        center: LatLng(lat, lon),
        radius: _kDepartureRadius,
      );

      // 내부 지오펜스: enter → 귀가 리셋
      final innerRegion = GeofenceCircularRegion(
        id: '$placeId$_kInnerSuffix',
        center: LatLng(lat, lon),
        radius: _kResetRadius,
      );

      await Geofencing.instance.start(regions: {outerRegion, innerRegion});
      _running = true;

      // 포그라운드 서비스 시작 — 백그라운드에서도 프로세스 유지
      if (!kIsWeb) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: '너머',
          notificationText: '위치를 확인하고 있어요',
        );
      }
    } catch (e) {
      debugPrint('[Geofence] start() failed (권한 미허용?): $e');
      return;
    }

    debugPrint(
      '[Geofence] Monitoring started — '
      'lat=$lat lon=$lon '
      'outer=${_kDepartureRadius}m inner=${_kResetRadius}m '
      'interval=${_kIntervalMs}ms',
    );
  }

  Future<void> stopMonitoring() async {
    if (!_running) return;
    _confirmTimer?.cancel();
    _confirmTimer = null;
    Geofencing.instance
        .removeGeofenceStatusChangedListener(_onGeofenceStatusChanged);
    await Geofencing.instance.stop();
    _running = false;
    if (!kIsWeb) await FlutterForegroundTask.stopService();
    debugPrint('[Geofence] Monitoring stopped');
  }

  /// 현재 이탈 감지 상태 (디버깅 / UI 표시용)
  bool get isPending  => _state == _DepartureState.pending;
  bool get isNotified => _state == _DepartureState.notified;
  bool get isAtHome   => _state == _DepartureState.atHome;
}
