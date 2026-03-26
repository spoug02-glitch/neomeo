// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'app/app.dart';
import 'app/router.dart';
import 'services/notification_service.dart';
import 'services/geofence_service_wrapper.dart';
import 'services/midnight_reset_worker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 포그라운드 서비스 초기화 (지오펜스 백그라운드 유지용)
  if (!kIsWeb) GeofenceServiceWrapper.initForegroundTask();

  // 알림은 runApp 전에 초기화해야 딥링크 핸들러가 동작함
  try {
    await NotificationService().init(
      onTap: (payload) {
        if (payload.startsWith('neomeo://checklist')) {
          final uri = Uri.tryParse(payload);
          final type = uri?.queryParameters['type'] ?? '나갈때';
          appRouter.go('/checklist?type=${Uri.encodeComponent(type)}');
        } else if (payload == 'neomeo://outing-select') {
          appRouter.go('/outing-select');
        }
      },
    );
  } catch (e) {
    debugPrint('[Main] Notification init failed: $e');
  }

  // 앱을 먼저 띄우고 나머지 초기화는 백그라운드에서 실행 (스플래시 단축)
  runApp(const ProviderScope(child: NeomeoApp()));

  if (!kIsWeb) {
    GeofenceServiceWrapper().startFromSaved().catchError(
      (e) => debugPrint('[Main] Geofence init failed: $e'),
    );
  }
  MidnightResetWorker.register().catchError(
    (e) => debugPrint('[Main] WorkManager init failed: $e'),
  );
}