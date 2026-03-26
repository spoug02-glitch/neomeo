// lib/features/settings/checklist_settings_screen.dart
//
// 장소당 "집 나갈 때" / "집 들어올 때" 2개 체크리스트 각각의 알림 설정 화면.
// outingType: '나갈때' → depart trigger, '들어올때' → enter trigger

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/prefs_service.dart';
import '../../app/design_system.dart';

class ChecklistSettingsScreen extends StatefulWidget {
  final String placeId;
  final String outingType; // '나갈때' or '들어올때'

  const ChecklistSettingsScreen({
    super.key,
    required this.placeId,
    required this.outingType,
  });

  @override
  State<ChecklistSettingsScreen> createState() => _ChecklistSettingsScreenState();
}

class _ChecklistSettingsScreenState extends State<ChecklistSettingsScreen> {
  bool _enabled = true;
  List<int> _days = [1, 2, 3, 4, 5];
  bool _isLoading = true;

  static const _dayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  // outingType → trigger 매핑
  String get _trigger =>
      widget.outingType == '나갈때' ? 'depart' : 'enter';

  String get _title =>
      widget.outingType == '나갈때' ? '집 나갈 때 설정' : '집 들어올 때 설정';

  String get _subtitle =>
      widget.outingType == '나갈때'
          ? '장소를 벗어날 때 체크리스트 알림을 받아요'
          : '장소에 돌아왔을 때 체크리스트 알림을 받아요';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final triggers = await PrefsService.getChecklistTriggers(widget.placeId);
    final days = await PrefsService.getChecklistTriggerDaysFor(
        widget.placeId, _trigger);

    if (mounted) {
      setState(() {
        _enabled = triggers.contains(_trigger);
        _days = days;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleEnabled(bool val) async {
    final triggers = await PrefsService.getChecklistTriggers(widget.placeId);
    final updated = Set<String>.from(triggers);
    if (val) {
      updated.add(_trigger);
    } else {
      updated.remove(_trigger);
    }
    await PrefsService.setChecklistTriggers(widget.placeId, updated.toList());
    setState(() => _enabled = val);
  }

  Future<void> _toggleDay(int day) async {
    final updated = List<int>.from(_days);
    if (updated.contains(day)) {
      updated.remove(day);
    } else {
      updated.add(day);
      updated.sort();
    }
    await PrefsService.setChecklistTriggerDaysFor(
        widget.placeId, _trigger, updated);
    setState(() => _days = updated);
  }

  bool get _isWeekdayOnly =>
      !_days.contains(0) && !_days.contains(6);

  Future<void> _toggleWeekdayOnly(bool val) async {
    final updated = val ? [1, 2, 3, 4, 5] : [0, 1, 2, 3, 4, 5, 6];
    await PrefsService.setChecklistTriggerDaysFor(
        widget.placeId, _trigger, updated);
    setState(() => _days = updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(_title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 알림 켜기/끄기 ───────────────────────────────
                _sectionHeader('알림 설정'),
                Card(
                  child: SwitchListTile(
                    title: Text(
                      widget.outingType == '나갈때'
                          ? '집 나갈 때 알림'
                          : '집 들어올 때 알림',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(_subtitle),
                    value: _enabled,
                    onChanged: _toggleEnabled,
                    activeColor: NeomeDesignSystem.primary,
                  ),
                ),

                // ── 알림 요일 ─────────────────────────────────────
                if (_enabled) ...[
                  const SizedBox(height: 20),
                  _sectionHeader('알림 요일'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              for (int i = 0; i < 7; i++)
                                Padding(
                                  padding: EdgeInsets.only(right: i < 6 ? 6 : 0),
                                  child: _DayChip(
                                    label: _dayLabels[i],
                                    selected: _days.contains(i),
                                    onTap: () => _toggleDay(i),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => _toggleWeekdayOnly(!_isWeekdayOnly),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _isWeekdayOnly,
                                    onChanged: (v) =>
                                        _toggleWeekdayOnly(v ?? false),
                                    activeColor: NeomeDesignSystem.primary,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '평일만 (월~금)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                // ── 안내 ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: Color(0xFF94A3B8)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '동일 알림은 1시간 이내에 반복 발송되지 않아요.\n'
                          '각 장소마다 나갈 때·들어올 때 체크리스트를 따로 설정할 수 있어요.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 4),
        child: Text(
          title,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: NeomeDesignSystem.textSub),
        ),
      );
}

// ── 요일 칩 ────────────────────────────────────────────────────

class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: selected
              ? NeomeDesignSystem.primary.withOpacity(0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? NeomeDesignSystem.primary
                : const Color(0xFFCBD5E1),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? NeomeDesignSystem.primary
                  : const Color(0xFFCBD5E1),
            ),
          ),
        ),
      ),
    );
  }
}
