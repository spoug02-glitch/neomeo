// lib/services/midnight_reset_worker.dart
//
// WorkManager 주기 태스크: 매일 새벽 03:00 (Asia/Seoul 기준) 에 실행
//   1. DailyNotifGuard 하루 알림 카운터 초기화
//   2. 체크리스트 세션 초기화
//
// 왜 자정이 아니라 03:00인가?
//   자정(00:00)은 사람이 아직 깨어 있을 가능성이 높고, 늦게 귀가한 후
//   체크리스트가 리셋되면 다음 날 외출 알림이 다시 가능해야 하므로
//   03:00을 기준으로 한다.
//
// WorkManager periodic task:
//   - 24시간 주기
//   - initialDelay = 다음 03:00까지 남은 시간
//   - existingWorkPolicy.keep → 앱을 다시 열어도 기존 일정 유지
//   - 배터리 최적화 제외 권한(onboarding에서 획득)이 있어야 정시 실행 보장

import 'package:workmanager/workmanager.dart';
import '../data/prefs_service.dart';
import 'daily_notif_guard.dart';

const kDailyResetTask = 'daily_reset_task';

/// WorkManager 백그라운드 진입점.
/// @pragma 어노테이션 필수 — tree-shaking 방지.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == kDailyResetTask) {
      // 1. 하루 알림 카운터 초기화
      await DailyNotifGuard.resetForNewDay();
      // 2. 체크리스트 세션 초기화 (새 날에는 새 체크리스트로 시작)
      await PrefsService.clearChecklistSession();
    }
    return true;
  });
}

class MidnightResetWorker {
  /// 앱 시작 시 한 번 호출한다.
  /// 이미 등록된 태스크가 있으면(keep) 그대로 유지하므로 중복 등록 안전.
  static Future<void> register() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

    // 구버전 oneOff 태스크 잔여분 취소 (이전 버전 호환)
    await Workmanager().cancelByUniqueName('midnight_reset_task');

    // 다음 03:00 (Asia/Seoul = UTC+9) 까지의 지연 계산
    final nowSeoul = DateTime.now().toUtc().add(const Duration(hours: 9));
    var nextReset = DateTime(
      nowSeoul.year,
      nowSeoul.month,
      nowSeoul.day,
      3, 0, 0, // 03:00:00
    );
    // 오늘 03:00이 이미 지났으면 내일로
    if (!nowSeoul.isBefore(nextReset)) {
      nextReset = nextReset.add(const Duration(days: 1));
    }
    final initialDelay = nextReset.difference(nowSeoul);

    await Workmanager().registerPeriodicTask(
      kDailyResetTask,
      kDailyResetTask,
      frequency: const Duration(hours: 24),
      initialDelay: initialDelay,
      constraints: Constraints(networkType: NetworkType.notRequired),
      // keep: 이미 등록되어 있으면 유지 → 앱 재시작 시 delay 재설정 방지
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
