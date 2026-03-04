// lib/services/midnight_reset_worker.dart
//
// WorkManager task: fires once per day near midnight (Asia/Seoul)
// to reset the DailyNotifGuard counter.
//
// Registration happens in main.dart.

import 'package:workmanager/workmanager.dart';
import 'daily_notif_guard.dart';

const kMidnightResetTask = 'midnight_reset_task';

/// Top‑level callback required by WorkManager (must be a @pragma function).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == kMidnightResetTask) {
      await DailyNotifGuard.resetForNewDay();
    }
    return Future.value(true);
  });
}

class MidnightResetWorker {
  /// Call once at app startup to register the periodic WorkManager task.
  static Future<void> register() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

    // Compute delay until next midnight (Asia/Seoul = UTC+9)
    final nowSeoul = DateTime.now().toUtc().add(const Duration(hours: 9));
    final midnight = DateTime(
      nowSeoul.year,
      nowSeoul.month,
      nowSeoul.day + 1,
      0, 0, 0,
    );
    final delay = midnight.difference(nowSeoul);

    await Workmanager().registerOneOffTask(
      kMidnightResetTask,
      kMidnightResetTask,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.notRequired),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}
