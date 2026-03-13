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

  // Notifications — set up tap deeplink handler
  try {
    await NotificationService().init(
      onTap: (payload) {
        // UT MVP: 알림 탭 시 등교 체크리스트로 바로 이동
        if (payload.startsWith('neomeo://checklist')) {
          const type = '등교';
          appRouter.go('/checklist?type=${Uri.encodeComponent(type)}');
        } else if (payload == 'neomeo://outing-select') {
          appRouter.go('/outing-select');
        }
      },
    );
  } catch (e) {
    debugPrint('[Main] Notification init failed: $e');
  }

  // Restart geofence if home was previously set
  if (!kIsWeb) {
    try {
      await GeofenceServiceWrapper().startFromSaved();
    } catch (e) {
      debugPrint('[Main] Geofence init failed: $e');
    }
  }

  // Register midnight reset WorkManager task
  try {
    await MidnightResetWorker.register();
  } catch (e) {
    debugPrint('[Main] WorkManager init failed: $e');
  }

  runApp(
    const ProviderScope(child: NeomeoApp()),
  );
}