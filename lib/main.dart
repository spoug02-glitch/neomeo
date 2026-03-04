// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'app/app.dart';
import 'app/router.dart';
import 'services/notification_service.dart';
import 'services/geofence_service_wrapper.dart';
import 'services/midnight_reset_worker.dart';
import 'data/prefs_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notifications — set up tap deeplink handler
  await NotificationService().init(
    onTap: (payload) {
      if (payload == 'neomeo://checklist') {
        appRouter.go('/checklist');
      }
    },
  );

  // Restart geofence if home was previously set
  if (!kIsWeb) {
  await GeofenceServiceWrapper().startFromSaved();
}

  // Register midnight reset WorkManager task
  await MidnightResetWorker.register();

  runApp(
    const ProviderScope(child: NeomeoApp()),
  );
}