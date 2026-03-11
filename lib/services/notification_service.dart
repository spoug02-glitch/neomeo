// lib/services/notification_service.dart
//
// Wraps flutter_local_notifications.
// Channel: geofence_channel (high importance).
// Deeplink payload: 'neomeo://checklist' → handled in main.dart via go_router.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'geofence_channel';
  static const _channelName = '너머 외출 알림';
  static const _channelDesc = '집을 나설 때 체크리스트 알림';

  // Called from main.dart — sets up channel + tap callback.
  Future<void> init({void Function(String payload)? onTap}) async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload ?? '';
        onTap?.call(payload);
      },
    );

    // Create Android notification channel
    // enableLights / enableVibration / showBadge 는 채널 생성 시에만 적용됨.
    // 채널이 이미 존재하면 시스템이 무시하므로, 앱 재설치 시 재생성된다.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
            enableVibration: true,
            enableLights: true,
            showBadge: true,
          ),
        );
  }

  /// Show the geofence exit alert (레거시 — 고정 메시지).
  Future<void> showGeofenceAlert() async {
    await showDepartureAlert(
      '외출 준비 됐나요? 🚪',
      '체크리스트를 확인하고 안심하게 떠나보세요.',
    );
  }

  /// 동적 메시지로 외출 알림을 발송한다.
  ///
  /// [title] 예) "가스불 확인했어?", "우산 챙겼어?"
  /// [body]  예) "체크리스트를 한 번 더 확인해봐요.", "비 올 것 같아요."
  Future<void> showDepartureAlert(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: '너머',
      visibility: NotificationVisibility.public, // 잠금화면에서도 전체 내용 표시
    );

    await _plugin.show(
      0,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: 'neomeo://checklist',
    );
  }

  /// 지오펜스 이탈 감지 시 외출 유형 선택을 유도하는 알림.
  /// 탭하면 /outing-select 화면으로 이동한다.
  Future<void> showDeparturePrompt() async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: '너머',
      visibility: NotificationVisibility.public,
    );

    await _plugin.show(
      0,
      '집을 나가는 것 같아요',
      '등교 전에 확인하고 가세요',
      const NotificationDetails(android: androidDetails),
      payload: 'neomeo://checklist?type=등교',
    );
  }
}
