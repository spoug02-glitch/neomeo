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
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );
  }

  /// Show the geofence exit alert.
  Future<void> showGeofenceAlert() async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: '너머',
    );

    await _plugin.show(
      0, // fixed id — ensures only one notification per day slot
      '외출 준비 됐나요? 🚪',
      '체크리스트를 확인하고 안심하게 떠나보세요.',
      const NotificationDetails(android: androidDetails),
      payload: 'neomeo://checklist',
    );
  }
}
