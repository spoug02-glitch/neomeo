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
  String _trigger = 'depart'; // 'depart' | 'enter' | 'time'
  String? _triggerTime;
  List<int> _triggerDays = [0, 1, 2, 3, 4, 5, 6]; // 0=일~6=토
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
    final trigger     = await PrefsService.getChecklistTrigger(_placeId);
    final triggerTime = await PrefsService.getChecklistTriggerTime(_placeId);
    final triggerDays = await PrefsService.getChecklistTriggerDays(_placeId);
    final places      = await PrefsService.getPlaces();
    final currentPlace = places.where((p) => p.id == _placeId).firstOrNull;

    if (mounted) {
      setState(() {
        _trigger     = trigger;
        _triggerTime = triggerTime;
        _triggerDays = triggerDays;
        _allPlaces   = places;
        _placeName   = currentPlace?.name ?? '장소';
        _isLoading   = false;
      });
    }
  }

  Future<void> _setTrigger(String val) async {
    await PrefsService.setChecklistTrigger(_placeId, val);
    setState(() => _trigger = val);
    if (val == 'time' && _triggerTime == null) {
      await _pickTime();
    }
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

  Future<void> _toggleDay(int day) async {
    final updated = List<int>.from(_triggerDays);
    if (updated.contains(day)) {
      updated.remove(day);
    } else {
      updated.add(day);
      updated.sort();
    }
    await PrefsService.setChecklistTriggerDays(_placeId, updated);
    setState(() => _triggerDays = updated);
  }

  /// 영업일 제외: 주말(일=0, 토=6) 제외, 월~금만 선택
  bool get _isWeekdayOnly =>
      !_triggerDays.contains(0) && !_triggerDays.contains(6);

  Future<void> _toggleWeekdayOnly(bool val) async {
    final updated = val
        ? [1, 2, 3, 4, 5]
        : [0, 1, 2, 3, 4, 5, 6];
    await PrefsService.setChecklistTriggerDays(_placeId, updated);
    setState(() => _triggerDays = updated);
  }

  Future<void> _pickPlace() async {
    if (_allPlaces.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
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
      await PrefsService.setChecklistTrigger(picked, _trigger);
      if (_triggerTime != null) {
        await PrefsService.setChecklistTriggerTime(picked, _triggerTime!);
      }
      await PrefsService.setChecklistTriggerDays(picked, _triggerDays);
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
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 알림 시점 ────────────────────────────────────────
              _sectionHeader('알림 시점'),
              Card(
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: _triggerTitle(' 나갈 때'),
                      subtitle: const Text('장소를 벗어날 때 알림을 받아요'),
                      value: 'depart',
                      groupValue: _trigger,
                      onChanged: (v) => _setTrigger(v!),
                      activeColor: NeomeDesignSystem.primary,
                    ),
                    const Divider(height: 1),
                    RadioListTile<String>(
                      title: _triggerTitle(' 들어올 때'),
                      subtitle: const Text('장소에 돌아왔을 때 알림을 받아요'),
                      value: 'enter',
                      groupValue: _trigger,
                      onChanged: (v) => _setTrigger(v!),
                      activeColor: NeomeDesignSystem.primary,
                    ),
                    const Divider(height: 1),
                    RadioListTile<String>(
                      title: Row(
                        children: [
                          const Text('특정 시간'),
                          if (_trigger == 'time' && _triggerTime != null) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _pickTime,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: NeomeDesignSystem.primary.withOpacity(0.1),
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
                      value: 'time',
                      groupValue: _trigger,
                      onChanged: (v) => _setTrigger(v!),
                      activeColor: NeomeDesignSystem.primary,
                    ),
                    // ── 요일 선택 (특정 시간 선택 시에만 표시) ──────
                    if (_trigger == 'time') ...[
                      const Divider(height: 1),
                      Padding(
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
                                // 일~토 토글 버튼
                                for (int i = 0; i < 7; i++)
                                  Padding(
                                    padding: EdgeInsets.only(right: i < 6 ? 6 : 0),
                                    child: _DayChip(
                                      label: _dayLabels[i],
                                      selected: _triggerDays.contains(i),
                                      onTap: () => _toggleDay(i),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                // 영업일 제외 체크박스
                                GestureDetector(
                                  onTap: () => _toggleWeekdayOnly(!_isWeekdayOnly),
                                  child: Row(
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
                                      const SizedBox(width: 4),
                                      const Text(
                                        '영업일 제외',
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
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// 장소명(밑줄+색)과 suffix 텍스트를 합쳐서 반환.
  Widget _triggerTitle(String suffix) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickPlace,
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 15, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
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
          color: selected
              ? NeomeDesignSystem.primary
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? NeomeDesignSystem.primary
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}
