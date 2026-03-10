// lib/features/checklist/checklist_screen.dart
//
// Shows a checklist for the selected outing type.
// Includes "다시 알림 받기" toggle that allows a 2nd geofence notification today.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/checklist_item.dart';
import '../../data/prefs_service.dart';
import '../../app/design_system.dart';
import '../../services/daily_notif_guard.dart';
import '../../services/weather_service.dart';
import '../../utils/recommendation_service.dart';

final _itemsProvider =
    StateNotifierProvider.family<ChecklistNotifier, List<ChecklistItem>, String>(
  (ref, type) => ChecklistNotifier(type),
);

final _extraProvider = StateProvider<bool>((ref) => false);

class ChecklistNotifier extends StateNotifier<List<ChecklistItem>> {
  ChecklistNotifier(String type) : super(_initializeItems(type)) {
    // 저장된 체크 상태를 복원한다. 세션이 없으면 현재 상태를 저장한다.
    _restoreFromPrefs();
  }

  static List<ChecklistItem> _initializeItems(String type) {
    final defaults = defaultItemsFor(type);
    final List<ChecklistItem> items = [];

    defaults.forEach((category, labels) {
      for (final label in labels) {
        if (items.length >= maxItems) break;
        items.add(ChecklistItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${items.length}',
          label: label,
          category: category,
        ));
      }
    });

    return items;
  }

  // ── 상태 저장 / 복원 ────────────────────────────────────────────────────────

  /// 저장된 세션에서 checked 상태를 복원한다.
  /// label이 일치하는 항목만 복원하므로 새 항목은 기본 미체크 상태를 유지한다.
  Future<void> _restoreFromPrefs() async {
    final saved = await PrefsService.getChecklistSession();
    if (saved.isEmpty) {
      _syncToPrefs();
      return;
    }
    final savedMap = <String, bool>{
      for (final s in saved)
        s['label'] as String: s['checked'] as bool? ?? false,
    };
    state = state.map((item) {
      final checked = savedMap[item.label];
      if (checked != null) {
        return ChecklistItem(
          id: item.id,
          label: item.label,
          category: item.category,
          checked: checked,
        );
      }
      return item;
    }).toList();
    _syncToPrefs();
  }

  /// 현재 체크리스트 상태를 SharedPreferences에 저장한다 (fire-and-forget).
  /// 외출 감지 콜백이 이 값을 읽어 알림 메시지를 결정한다.
  void _syncToPrefs() {
    final snapshot = state
        .map((i) => {'label': i.label, 'checked': i.checked})
        .toList();
    PrefsService.saveChecklistSession(snapshot); // async, 결과 무시
  }

  // ── 상태 변이 ─────────────────────────────────────────────────────────────

  void toggle(String id) {
    state = state.map((item) {
      if (item.id == id) {
        return ChecklistItem(
          id: item.id,
          label: item.label,
          category: item.category,
          checked: !item.checked,
        );
      }
      return item;
    }).toList();
    _syncToPrefs();
  }

  static const maxItems = 5;

  bool get isFull => state.length >= maxItems;

  void add(String label, String category) {
    if (label.trim().isEmpty) return;
    if (isFull) return;
    state = [
      ...state,
      ChecklistItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        label: label.trim(),
        category: category,
      )
    ];
    _syncToPrefs();
  }

  void remove(String id) {
    state = state.where((i) => i.id != id).toList();
    _syncToPrefs();
  }

  Future<void> addAutoItems() async {
    final weatherEnabled = await PrefsService.isWeatherEnabled();
    final dustEnabled = await PrefsService.isDustEnabled();
    if (!weatherEnabled && !dustEnabled) return;

    final apiKey = await PrefsService.getWeatherApiKey();
    if (apiKey.isEmpty) return;

    final activePlace = await PrefsService.getActivePlace();
    if (activePlace == null) return;

    if (weatherEnabled) {
      final weatherData = await WeatherService.fetchWeather(activePlace.lat, activePlace.lon, apiKey);
      if (WeatherService.shouldBringUmbrella(weatherData)) {
        if (!state.any((item) => item.label == '우산')) {
          add('우산', '준비물'); // add() 내부에서 _syncToPrefs() 호출됨
        }
      }
    }

    if (dustEnabled) {
      final airData = await WeatherService.fetchAirPollution(activePlace.lat, activePlace.lon, apiKey);
      if (WeatherService.shouldWearMask(airData)) {
        if (!state.any((item) => item.label == '마스크')) {
          add('마스크', '준비물'); // add() 내부에서 _syncToPrefs() 호출됨
        }
      }
    }
  }

  /// 설정 상태 기반 추천 아이템을 체크리스트에 자동 추가한다 (mock, API 호출 없음).
  Future<void> addRecommendedItems() async {
    final recs = await RecommendationService.getTodayRecommendations();
    for (final item in recs) {
      if (!state.any((i) => i.label == item)) {
        add(item, '준비물');
      }
    }
  }
}

class ChecklistScreen extends ConsumerStatefulWidget {
  final String outingType;
  const ChecklistScreen({super.key, required this.outingType});

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  final _addCtrl = TextEditingController();
  String _selectedCategory = '준비물';

  @override
  void initState() {
    super.initState();
    _loadExtraState();
  }

  Future<void> _loadExtraState() async {
    final isExtra = await DailyNotifGuard.isExtraAllowed();
    ref.read(_extraProvider.notifier).state = isExtra;
    
    // Trigger auto-items check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(_itemsProvider(widget.outingType).notifier);
      notifier.addRecommendedItems();
      notifier.addAutoItems();
    });
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 모든 항목이 체크되는 순간 완료 피드백 표시
    ref.listen<List<ChecklistItem>>(
      _itemsProvider(widget.outingType),
      (previous, next) {
        if (next.isEmpty) return;
        final total = next.length;
        final checked = next.where((i) => i.checked).length;
        final prevChecked = previous?.where((i) => i.checked).length ?? 0;
        if (checked == total && prevChecked < total) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '오늘 준비 끝! 👍',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: NeomeDesignSystem.primary,
            ),
          );
        }
      },
    );

    final items = ref.watch(_itemsProvider(widget.outingType));
    final notifier = ref.read(_itemsProvider(widget.outingType).notifier);
    final checkedCount = items.where((i) => i.checked).length;
    final total = items.length;
    final progress = total == 0 ? 0.0 : checkedCount / total;
    final extraAllowed = ref.watch(_extraProvider);

    return Scaffold(
      backgroundColor: NeomeDesignSystem.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // ── Header ──────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => context.go('/home'),
                            icon: const Icon(Icons.chevron_left, size: 18),
                            label: const Text('뒤로'),
                            style: TextButton.styleFrom(
                              foregroundColor: NeomeDesignSystem.textSub,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: NeomeDesignSystem.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              widget.outingType,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: NeomeDesignSystem.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Title + progress ─────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '준비물 확인',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '필요한 것을 챙겼는지 확인해요',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: NeomeDesignSystem.border,
                                    color: NeomeDesignSystem.primary,
                                    minHeight: 8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '$checkedCount / $total',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Supplies Section ──────────────────────────
                  _buildCategorySection(items, '준비물', notifier),

                  // ── Actions Section ───────────────────────────
                  _buildCategorySection(items, '행동', notifier),

                  // ── Add item ─────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: total >= ChecklistNotifier.maxItems
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                '항목은 최대 ${ChecklistNotifier.maxItems}개까지 추가할 수 있어요',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                              ),
                            )
                          : Card(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                                child: Row(
                                  children: [
                                    // 카테고리 드롭다운
                                    DropdownButton<String>(
                                      value: _selectedCategory,
                                      underline: const SizedBox(),
                                      isDense: true,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: NeomeDesignSystem.primary,
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: '준비물', child: Text('준비물')),
                                        DropdownMenuItem(value: '행동', child: Text('행동')),
                                      ],
                                      onChanged: (v) => setState(() => _selectedCategory = v!),
                                    ),
                                    const SizedBox(width: 8),
                                    // 입력 필드
                                    Expanded(
                                      child: TextField(
                                        controller: _addCtrl,
                                        decoration: InputDecoration(
                                          hintText: '$_selectedCategory 추가...',
                                          hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                                          border: InputBorder.none,
                                        ),
                                        onSubmitted: (v) {
                                          notifier.add(v, _selectedCategory);
                                          _addCtrl.clear();
                                        },
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        if (_addCtrl.text.isNotEmpty) {
                                          notifier.add(_addCtrl.text, _selectedCategory);
                                          _addCtrl.clear();
                                        }
                                      },
                                      child: const Text('추가'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),

                  // ── 다시 알림 받기 toggle ─────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Card(
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                          title: const Text(
                            '다시 알림 받기',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                          subtitle: const Text(
                            '오늘 집을 나설 때 알림을 한 번 더 받아요',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                          value: extraAllowed,
                          activeColor: NeomeDesignSystem.primary,
                          onChanged: (val) async {
                            ref.read(_extraProvider.notifier).state = val;
                            if (val) {
                              await DailyNotifGuard.allowExtraToday();
                            } else {
                              await DailyNotifGuard.disallowExtra();
                            }
                          },
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              ),
            ),

            // ── Depart button ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: FilledButton(
                onPressed: checkedCount == total && total > 0
                    ? () => context.go('/home')
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: NeomeDesignSystem.primary,
                  disabledBackgroundColor: NeomeDesignSystem.border,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                child: const Text('출발해요'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(List<ChecklistItem> items, String category, ChecklistNotifier notifier) {
    final filteredItems = items.where((i) => i.category == category).toList();
    if (filteredItems.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                category,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
            Card(
              child: Column(
                children: filteredItems.asMap().entries.map((e) {
                  final item = e.value;
                  return Column(
                    children: [
                      if (e.key > 0)
                        Divider(height: 1, color: Colors.grey.shade50),
                      _buildItemTile(item, notifier),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(ChecklistItem item, ChecklistNotifier notifier) {
    return ListTile(
      onTap: () {
        HapticFeedback.lightImpact();
        notifier.toggle(item.id);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 175),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: item.checked ? NeomeDesignSystem.primary : Colors.white,
          border: Border.all(
            color: item.checked ? NeomeDesignSystem.primary : NeomeDesignSystem.border,
            width: 2,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 175),
          child: item.checked
              ? const Icon(Icons.check, key: ValueKey(true), size: 14, color: Colors.white)
              : const SizedBox.shrink(key: ValueKey(false)),
        ),
      ),
      title: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 175),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: item.checked ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
          decoration: item.checked ? TextDecoration.lineThrough : TextDecoration.none,
          decorationColor: const Color(0xFFCBD5E1),
        ),
        child: Text(item.label),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18, color: Color(0xFFCBD5E1)),
        onPressed: () => notifier.remove(item.id),
        tooltip: '삭제',
      ),
    );
  }
}
