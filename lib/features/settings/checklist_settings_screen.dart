// lib/features/settings/checklist_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/prefs_service.dart';
import '../../data/place.dart';
import '../../app/design_system.dart';

class ChecklistSettingsScreen extends StatefulWidget {
  final String placeId;
  final String outingType;

  const ChecklistSettingsScreen({
    super.key,
    required this.placeId,
    required this.outingType,
  });

  @override
  State<ChecklistSettingsScreen> createState() => _ChecklistSettingsScreenState();
}

class _ChecklistSettingsScreenState extends State<ChecklistSettingsScreen> {
  Set<String> _triggers = {'depart'};
  String? _triggerTime;
  // 트리거별 요일 맵. 기본값: 월~금 [1,2,3,4,5]
  Map<String, List<int>> _daysFor = {
    'depart': [1, 2, 3, 4, 5],
    'enter':  [1, 2, 3, 4, 5],
    'time':   [1, 2, 3, 4, 5],
  };
  String _placeId = '';
  String _placeName = '';
  List<Place> _allPlaces = [];
  bool _isLoading = true;

  static const _dayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  void initState() {
    super.initState();
    _placeId = widget.placeId;
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      PrefsService.getChecklistTriggers(_placeId),
      PrefsService.getChecklistTriggerTime(_placeId),
      PrefsService.getChecklistTriggerDaysFor(_placeId, 'depart'),
      PrefsService.getChecklistTriggerDaysFor(_placeId, 'enter'),
      PrefsService.getChecklistTriggerDaysFor(_placeId, 'time'),
      PrefsService.getPlaces(),
    ]);

    final triggers    = results[0] as List<String>;
    final triggerTime = results[1] as String?;
    final departDays  = results[2] as List<int>;
    final enterDays   = results[3] as List<int>;
    final timeDays    = results[4] as List<int>;
    final places      = results[5] as List<Place>;
    final currentPlace = places.where((p) => p.id == _placeId).firstOrNull;

    if (mounted) {
      setState(() {
        _triggers    = triggers.toSet();
        _triggerTime = triggerTime;
        _daysFor = {
          'depart': departDays,
          'enter':  enterDays,
          'time':   timeDays,
        };
        _allPlaces   = places;
        _placeName   = currentPlace?.name ?? '장소';
        _isLoading   = false;
      });
    }
  }

  Future<void> _toggleTrigger(String val) async {
    final updated = Set<String>.from(_triggers);
    if (updated.contains(val)) {
      if (updated.length == 1) return;
      updated.remove(val);
    } else {
      updated.add(val);
      if (val == 'time' && _triggerTime == null) {
        await _pickTime();
      }
    }
    await PrefsService.setChecklistTriggers(_placeId, updated.toList());
    setState(() => _triggers = updated);
  }

  Future<void> _pickTime() async {
    TimeOfDay initial = TimeOfDay.now();
    if (_triggerTime != null) {
      final parts = _triggerTime!.split(':');
      initial = TimeOfDay(
          hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      final timeStr =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      await PrefsService.setChecklistTriggerTime(_placeId, timeStr);
      setState(() => _triggerTime = timeStr);
    }
  }

  Future<void> _toggleDayFor(String trigger, int day) async {
    final current = List<int>.from(_daysFor[trigger] ?? [1, 2, 3, 4, 5]);
    if (current.contains(day)) {
      current.remove(day);
    } else {
      current.add(day);
      current.sort();
    }
    await PrefsService.setChecklistTriggerDaysFor(_placeId, trigger, current);
    setState(() => _daysFor[trigger] = current);
  }

  bool _isWeekdayOnlyFor(String trigger) {
    final days = _daysFor[trigger] ?? [];
    return !days.contains(0) && !days.contains(6);
  }

  Future<void> _toggleWeekdayOnlyFor(String trigger, bool val) async {
    final updated = val ? [1, 2, 3, 4, 5] : [0, 1, 2, 3, 4, 5, 6];
    await PrefsService.setChecklistTriggerDaysFor(_placeId, trigger, updated);
    setState(() => _daysFor[trigger] = updated);
  }

  Future<void> _pickPlace() async {
    if (_allPlaces.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E8EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('장소 선택',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          for (final p in _allPlaces)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(p.name),
              trailing: p.id == _placeId
                  ? const Icon(Icons.check, color: NeomeDesignSystem.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, p.id),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (picked != null && picked != _placeId) {
      final place = _allPlaces.firstWhere((p) => p.id == picked);
      await PrefsService.setChecklistTriggers(picked, _triggers.toList());
      if (_triggerTime != null) {
        await PrefsService.setChecklistTriggerTime(picked, _triggerTime!);
      }
      for (final trigger in ['depart', 'enter', 'time']) {
        final days = _daysFor[trigger];
        if (days != null) {
          await PrefsService.setChecklistTriggerDaysFor(picked, trigger, days);
        }
      }
      setState(() {
        _placeId   = picked;
        _placeName = place.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasTime = _triggers.contains('time');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('${widget.outingType} 체크리스트 설정',
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
                _sectionHeader('알림 시점'),
                Card(
                  child: Column(
                    children: [
                      // ── 집 나갈 때 ──────────────────────────────────
                      CheckboxListTile(
                        title: _triggerTitle(' 나갈 때'),
                        subtitle: const Text('장소를 벗어날 때 알림을 받아요'),
                        value: _triggers.contains('depart'),
                        onChanged: (_) => _toggleTrigger('depart'),
                        activeColor: NeomeDesignSystem.primary,
                        checkboxShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (_triggers.contains('depart')) ...[
                        const Divider(height: 1),
                        _buildDayPicker('depart'),
                      ],
                      const Divider(height: 1),
                      // ── 집 들어올 때 ────────────────────────────────
                      CheckboxListTile(
                        title: _triggerTitle(' 들어올 때'),
                        subtitle: const Text('장소에 돌아왔을 때 알림을 받아요'),
                        value: _triggers.contains('enter'),
                        onChanged: (_) => _toggleTrigger('enter'),
                        activeColor: NeomeDesignSystem.primary,
                        checkboxShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (_triggers.contains('enter')) ...[
                        const Divider(height: 1),
                        _buildDayPicker('enter'),
                      ],
                      const Divider(height: 1),
                      // ── 특정 시간 ────────────────────────────────────
                      CheckboxListTile(
                        title: Row(
                          children: [
                            const Text('특정 시간'),
                            if (hasTime && _triggerTime != null) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _pickTime,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: NeomeDesignSystem.primary
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _triggerTime!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: NeomeDesignSystem.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: const Text('설정한 요일과 시간에 알림을 받아요'),
                        value: hasTime,
                        onChanged: (_) => _toggleTrigger('time'),
                        activeColor: NeomeDesignSystem.primary,
                        checkboxShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (hasTime) ...[
                        const Divider(height: 1),
                        _buildDayPicker('time'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          '나갈 때, 들어올 때, 특정 시간을 동시에 선택할 수 있어요.\n동일 알림은 1시간 이내에 반복 발송되지 않아요.',
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

  /// 트리거 아래 인라인으로 보여주는 요일 선택 패널
  Widget _buildDayPicker(String trigger) {
    final days = _daysFor[trigger] ?? [1, 2, 3, 4, 5];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '요일 선택',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < 7; i++)
                Padding(
                  padding: EdgeInsets.only(right: i < 6 ? 6 : 0),
                  child: _DayChip(
                    label: _dayLabels[i],
                    selected: days.contains(i),
                    onTap: () => _toggleDayFor(trigger, i),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _toggleWeekdayOnlyFor(trigger, !_isWeekdayOnlyFor(trigger)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _isWeekdayOnlyFor(trigger),
                    onChanged: (v) =>
                        _toggleWeekdayOnlyFor(trigger, v ?? false),
                    activeColor: NeomeDesignSystem.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '평일만',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _triggerTitle(String suffix) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickPlace,
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF1E293B),
              fontWeight: FontWeight.w500),
          children: [
            TextSpan(
              text: _placeName,
              style: TextStyle(
                color: NeomeDesignSystem.primary.withOpacity(0.55),
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: NeomeDesignSystem.primary.withOpacity(0.35),
              ),
            ),
            TextSpan(text: suffix),
          ],
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
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
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
              fontSize: 12,
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
