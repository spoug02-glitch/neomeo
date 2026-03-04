// lib/features/checklist/checklist_screen.dart
//
// Shows a checklist for the selected outing type.
// Includes "다시 알림 받기" toggle that allows a 2nd geofence notification today.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/checklist_item.dart';
import '../../data/prefs_service.dart';
import '../../app/design_system.dart';
import '../../services/daily_notif_guard.dart';
import '../../services/weather_service.dart';

final _itemsProvider =
    StateNotifierProvider.family<ChecklistNotifier, List<ChecklistItem>, String>(
  (ref, type) => ChecklistNotifier(type),
);

final _extraProvider = StateProvider<bool>((ref) => false);

class ChecklistNotifier extends StateNotifier<List<ChecklistItem>> {
  ChecklistNotifier(String type) : super(_initializeItems(type));

  static List<ChecklistItem> _initializeItems(String type) {
    final defaults = defaultItemsFor(type);
    final List<ChecklistItem> items = [];

    defaults.forEach((category, labels) {
      for (final label in labels) {
        items.add(ChecklistItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${items.length}',
          label: label,
          category: category,
        ));
      }
    });

    return items;
  }

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
  }

  void add(String label, String category) {
    if (label.trim().isEmpty) return;
    state = [
      ...state,
      ChecklistItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        label: label.trim(),
        category: category,
      )
    ];
  }

  void remove(String id) {
    state = state.where((i) => i.id != id).toList();
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
          add('우산', '준비물');
        }
      }
    }

    if (dustEnabled) {
      final airData = await WeatherService.fetchAirPollution(activePlace.lat, activePlace.lon, apiKey);
      if (WeatherService.shouldWearMask(airData)) {
        if (!state.any((item) => item.label == '마스크')) {
          add('마스크', '준비물');
        }
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
      ref.read(_itemsProvider(widget.outingType).notifier).addAutoItems();
    });
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _addCtrl,
                                  decoration: const InputDecoration(
                                    hintText: '준비물 추가...',
                                    hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (v) {
                                    notifier.add(v, '준비물');
                                    _addCtrl.clear();
                                  },
                                ),
                                ),
                              TextButton(
                                onPressed: () {
                                  if (_addCtrl.text.isNotEmpty) {
                                    notifier.add(_addCtrl.text, '준비물');
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
                          activeColor: const Color(0xFF6366F1),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: GestureDetector(
        onTap: () => notifier.toggle(item.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
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
          child: item.checked ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
        ),
      ),
      title: Text(
        item.label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: item.checked ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
          decoration: item.checked ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18, color: Color(0xFFCBD5E1)),
        onPressed: () => notifier.remove(item.id),
        tooltip: '삭제',
      ),
    );
  }
}
