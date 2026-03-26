// lib/features/calendar/add_event_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../app/design_system.dart';
import '../../data/local_event.dart';
import '../../services/calendar_service.dart';

/// Shows the add-event bottom sheet and returns the saved [LocalEvent],
/// or null if cancelled.
Future<LocalEvent?> showAddEventSheet(
  BuildContext context, {
  DateTime? initialDate,
  String? parentEventId,
}) {
  return showModalBottomSheet<LocalEvent>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddEventSheet(
      initialDate: initialDate ?? DateTime.now(),
      parentEventId: parentEventId,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
class _AddEventSheet extends StatefulWidget {
  final DateTime initialDate;
  final String? parentEventId;

  const _AddEventSheet({required this.initialDate, this.parentEventId});

  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final _service = CalendarService();
  final _titleCtrl = TextEditingController();

  bool _isChecklistMode = true;
  late DateTime _date;
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay? _endTime;
  EventImportance _importance = EventImportance.none;
  RepeatType _repeatType = RepeatType.none;
  List<int> _repeatDays = [];
  bool _repeatExcludeWeekends = false;

  // Checklist items
  final List<_ItemEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────
  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final startDt = DateTime(
      _date.year, _date.month, _date.day,
      _startTime.hour, _startTime.minute,
    );
    DateTime? endDt;
    if (_endTime != null) {
      endDt = DateTime(
        _date.year, _date.month, _date.day,
        _endTime!.hour, _endTime!.minute,
      );
    }

    final checklistItems = _items.map((e) => LocalEventItem(
      label: e.ctrl.text.trim(),
      deadline: e.deadline,
    )).where((i) => i.label.isNotEmpty).toList();

    final event = LocalEvent(
      title: title,
      startTime: startDt,
      endTime: endDt,
      importance: _importance,
      repeatType: _repeatType,
      repeatDays: _repeatDays,
      repeatExcludeWeekends: _repeatExcludeWeekends,
      isChecklistMode: _isChecklistMode,
      checklistItems: checklistItems,
      parentEventId: widget.parentEventId,
    );

    await _service.saveEvent(event);
    if (mounted) Navigator.of(context).pop(event);
  }

  // ── Date / Time helpers ───────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ko'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startTime : (_endTime ?? _startTime);
    final picked = await _showDrumTimePicker(context, initial);
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  // ── Checklist item deadline ───────────────────────────────
  Future<void> _pickItemDeadline(_ItemEntry entry) async {
    final result = await showDialog<_DeadlineResult>(
      context: context,
      builder: (_) => _DeadlineDialog(eventDate: _date),
    );
    if (result != null) {
      setState(() => entry.deadline = result.deadline);
    }
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.08),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: NeomeDesignSystem.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.parentEventId != null ? '후속 일정 추가' : '새 일정 추가',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소', style: TextStyle(color: NeomeDesignSystem.textSub)),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: NeomeDesignSystem.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Text('저장'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  _sectionLabel('일정 제목'),
                  TextField(
                    controller: _titleCtrl,
                    autofocus: true,
                    style: NeomeDesignSystem.body1,
                    decoration: _inputDecor('예: 미팅, 운동'),
                  ),
                  const SizedBox(height: 20),

                  // Mode toggle
                  _sectionLabel('유형'),
                  _buildModeToggle(),
                  const SizedBox(height: 20),

                  // Checklist items (only in checklist mode)
                  if (_isChecklistMode) ...[
                    _sectionLabel('체크리스트 항목'),
                    _buildChecklistSection(),
                    const SizedBox(height: 20),
                  ],

                  // Date
                  _sectionLabel('날짜'),
                  _buildDateRow(),
                  const SizedBox(height: 20),

                  // Time
                  _sectionLabel('시간'),
                  _buildTimeRow(),
                  const SizedBox(height: 20),

                  // Importance
                  _sectionLabel('중요도'),
                  _buildImportanceChips(),
                  const SizedBox(height: 20),

                  // Repeat
                  _sectionLabel('반복'),
                  _buildRepeatSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode toggle ───────────────────────────────────────────
  Widget _buildModeToggle() {
    return Row(
      children: [
        _ModeChip(
          label: '체크리스트',
          icon: Icons.checklist,
          selected: _isChecklistMode,
          onTap: () => setState(() => _isChecklistMode = true),
        ),
        const SizedBox(width: 8),
        _ModeChip(
          label: '메모',
          icon: Icons.notes,
          selected: !_isChecklistMode,
          onTap: () => setState(() => _isChecklistMode = false),
        ),
      ],
    );
  }

  // ── Checklist section ─────────────────────────────────────
  Widget _buildChecklistSection() {
    return Column(
      children: [
        ..._items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: NeomeDesignSystem.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.drag_handle, size: 18, color: NeomeDesignSystem.textHint),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: item.ctrl,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: '항목 입력',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                // Deadline button
                GestureDetector(
                  onTap: () => _pickItemDeadline(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: item.deadline != null
                          ? NeomeDesignSystem.primary.withOpacity(0.1)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: item.deadline != null
                            ? NeomeDesignSystem.primary.withOpacity(0.3)
                            : NeomeDesignSystem.border,
                      ),
                    ),
                    child: Text(
                      item.deadline != null
                          ? DateFormat('M/d HH:mm').format(item.deadline!)
                          : '기한',
                      style: TextStyle(
                        fontSize: 11,
                        color: item.deadline != null
                            ? NeomeDesignSystem.primary
                            : NeomeDesignSystem.textHint,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: NeomeDesignSystem.textHint),
                  onPressed: () => setState(() => _items.removeAt(idx)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          );
        }),
        // Add item button
        GestureDetector(
          onTap: () => setState(() => _items.add(_ItemEntry())),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline,
                    size: 18, color: NeomeDesignSystem.primary.withOpacity(0.7)),
                const SizedBox(width: 8),
                Text(
                  '항목 추가',
                  style: TextStyle(
                    fontSize: 13,
                    color: NeomeDesignSystem.primary.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Date row ──────────────────────────────────────────────
  Widget _buildDateRow() {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: NeomeDesignSystem.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: NeomeDesignSystem.textSub),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(_date),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: NeomeDesignSystem.textHint),
          ],
        ),
      ),
    );
  }

  // ── Time row ──────────────────────────────────────────────
  Widget _buildTimeRow() {
    return Row(
      children: [
        Expanded(
          child: _TimeTile(
            label: '시작',
            time: _startTime,
            onTap: () => _pickTime(isStart: true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TimeTile(
            label: '종료',
            time: _endTime,
            onTap: () => _pickTime(isStart: false),
          ),
        ),
      ],
    );
  }

  // ── Importance chips ──────────────────────────────────────
  Widget _buildImportanceChips() {
    const opts = [
      (EventImportance.none,   '없음',   Color(0xFF94A3B8)),
      (EventImportance.medium, '보통',   Color(0xFF22C55E)),
      (EventImportance.high,   '중요',   Color(0xFFF97316)),
    ];
    return Row(
      children: opts.map((t) {
        final (imp, label, color) = t;
        final sel = _importance == imp;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _importance = imp),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? color.withOpacity(0.12) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? color : NeomeDesignSystem.border,
                  width: sel ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? color : NeomeDesignSystem.textSub,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Repeat section ────────────────────────────────────────
  Widget _buildRepeatSection() {
    const opts = [
      (RepeatType.none,       '없음'),
      (RepeatType.daily,      '매일'),
      (RepeatType.weeklyDays, '매주 선택'),
      (RepeatType.weekly,     '일주일마다'),
      (RepeatType.monthly,    '매달'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opts.map(((t, label)) {
            final sel = _repeatType == t;
            return GestureDetector(
              onTap: () => setState(() {
                _repeatType = t;
                if (t == RepeatType.weeklyDays && _repeatDays.isEmpty) {
                  _repeatDays = [1, 2, 3, 4, 5]; // default Mon–Fri
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel
                      ? NeomeDesignSystem.primary.withOpacity(0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? NeomeDesignSystem.primary : NeomeDesignSystem.border,
                    width: sel ? 1.5 : 1.0,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sel
                        ? NeomeDesignSystem.primary
                        : NeomeDesignSystem.textSub,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // weeklyDays sub-options
        if (_repeatType == RepeatType.weeklyDays) ...[
          const SizedBox(height: 14),
          _buildDayPicker(),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(
                () => _repeatExcludeWeekends = !_repeatExcludeWeekends),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _repeatExcludeWeekends,
                    onChanged: (v) =>
                        setState(() => _repeatExcludeWeekends = v ?? false),
                    activeColor: NeomeDesignSystem.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '영업일 제외 (주말 건너뜀)',
                  style: TextStyle(fontSize: 13, color: NeomeDesignSystem.textSub),
                ),
              ],
            ),
          ),
        ],

        // daily: exclude weekends option
        if (_repeatType == RepeatType.daily) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(
                () => _repeatExcludeWeekends = !_repeatExcludeWeekends),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _repeatExcludeWeekends,
                    onChanged: (v) =>
                        setState(() => _repeatExcludeWeekends = v ?? false),
                    activeColor: NeomeDesignSystem.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '영업일만 반복 (주말 제외)',
                  style: TextStyle(fontSize: 13, color: NeomeDesignSystem.textSub),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDayPicker() {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    return Row(
      children: List.generate(7, (i) {
        final selected = _repeatDays.contains(i);
        return Padding(
          padding: EdgeInsets.only(right: i < 6 ? 6 : 0),
          child: GestureDetector(
            onTap: () => setState(() {
              if (selected) {
                _repeatDays = _repeatDays.where((d) => d != i).toList();
              } else {
                _repeatDays = [..._repeatDays, i]..sort();
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? NeomeDesignSystem.primary.withOpacity(0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? NeomeDesignSystem.primary
                      : NeomeDesignSystem.border,
                  width: selected ? 1.5 : 1.0,
                ),
              ),
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? NeomeDesignSystem.primary
                        : NeomeDesignSystem.textSub,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: NeomeDesignSystem.textSub,
          ),
        ),
      );

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: NeomeDesignSystem.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: NeomeDesignSystem.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}

// ─────────────────────────────────────────────────────────────
// Drum-roll time picker
// ─────────────────────────────────────────────────────────────
Future<TimeOfDay?> _showDrumTimePicker(
    BuildContext context, TimeOfDay initial) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _DrumTimePicker(initial: initial),
  );
}

class _DrumTimePicker extends StatefulWidget {
  final TimeOfDay initial;
  const _DrumTimePicker({required this.initial});

  @override
  State<_DrumTimePicker> createState() => _DrumTimePickerState();
}

class _DrumTimePickerState extends State<_DrumTimePicker> {
  late int _hour;
  late int _minute;
  bool _textMode = false;
  final _hourCtrl   = TextEditingController();
  final _minuteCtrl = TextEditingController();

  late final FixedExtentScrollController _hourScroll;
  late final FixedExtentScrollController _minuteScroll;

  @override
  void initState() {
    super.initState();
    _hour   = widget.initial.hour;
    _minute = widget.initial.minute;
    _hourScroll   = FixedExtentScrollController(initialItem: _hour);
    _minuteScroll = FixedExtentScrollController(initialItem: _minute);
    _hourCtrl.text   = _hour.toString().padLeft(2, '0');
    _minuteCtrl.text = _minute.toString().padLeft(2, '0');
  }

  @override
  void dispose() {
    _hourScroll.dispose();
    _minuteScroll.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_textMode) {
      final h = int.tryParse(_hourCtrl.text) ?? _hour;
      final m = int.tryParse(_minuteCtrl.text) ?? _minute;
      _hour   = h.clamp(0, 23);
      _minute = m.clamp(0, 59);
    }
    Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소',
                      style: TextStyle(color: NeomeDesignSystem.textSub)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _textMode = !_textMode),
                  child: Text(
                    _textMode ? '스크롤 입력' : '직접 입력',
                    style: const TextStyle(
                        color: NeomeDesignSystem.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _submit,
                  child: const Text('확인',
                      style: TextStyle(
                          color: NeomeDesignSystem.primary,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          if (_textMode)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _textField(_hourCtrl, 'HH'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(':',
                        style: TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w300)),
                  ),
                  _textField(_minuteCtrl, 'MM'),
                ],
              ),
            )
          else
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _hourScroll,
                      itemExtent: 44,
                      perspective: 0.003,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (i) =>
                          setState(() => _hour = i),
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (_, i) => Center(
                          child: Text(
                            i.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: _hour == i
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _hour == i
                                  ? NeomeDesignSystem.textMain
                                  : NeomeDesignSystem.textHint,
                            ),
                          ),
                        ),
                        childCount: 24,
                      ),
                    ),
                  ),
                  const Text(':',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w300)),
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _minuteScroll,
                      itemExtent: 44,
                      perspective: 0.003,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (i) =>
                          setState(() => _minute = i),
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (_, i) => Center(
                          child: Text(
                            i.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: _minute == i
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _minute == i
                                  ? NeomeDesignSystem.textMain
                                  : NeomeDesignSystem.textHint,
                            ),
                          ),
                        ),
                        childCount: 60,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String hint) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: NeomeDesignSystem.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Item deadline dialog
// ─────────────────────────────────────────────────────────────
class _DeadlineResult {
  final DateTime deadline;
  _DeadlineResult(this.deadline);
}

class _DeadlineDialog extends StatefulWidget {
  final DateTime eventDate;
  const _DeadlineDialog({required this.eventDate});

  @override
  State<_DeadlineDialog> createState() => _DeadlineDialogState();
}

class _DeadlineDialogState extends State<_DeadlineDialog> {
  bool _useRelative = true;
  int _daysBefore = 1;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _absoluteDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('완료 기한 설정',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _useRelative = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _useRelative
                          ? NeomeDesignSystem.primary
                          : NeomeDesignSystem.background,
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(10)),
                    ),
                    child: Center(
                      child: Text(
                        '일정 기준',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _useRelative
                              ? Colors.white
                              : NeomeDesignSystem.textSub,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _useRelative = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !_useRelative
                          ? NeomeDesignSystem.primary
                          : NeomeDesignSystem.background,
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(10)),
                    ),
                    child: Center(
                      child: Text(
                        '날짜 지정',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: !_useRelative
                              ? Colors.white
                              : NeomeDesignSystem.textSub,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_useRelative) ...[
            Row(
              children: [
                const Text('일정 기준 ', style: TextStyle(fontSize: 14)),
                const Text('-', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(
                  width: 48,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      border: UnderlineInputBorder(),
                    ),
                    controller: TextEditingController(text: '$_daysBefore'),
                    onChanged: (v) => _daysBefore = int.tryParse(v) ?? 1,
                  ),
                ),
                const Text(' 일 전', style: TextStyle(fontSize: 14)),
              ],
            ),
          ] else ...[
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _absoluteDate ?? widget.eventDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _absoluteDate = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: NeomeDesignSystem.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _absoluteDate != null
                          ? DateFormat('yyyy년 M월 d일').format(_absoluteDate!)
                          : '날짜 선택',
                      style: TextStyle(
                        fontSize: 14,
                        color: _absoluteDate != null
                            ? NeomeDesignSystem.textMain
                            : NeomeDesignSystem.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Time
          GestureDetector(
            onTap: () async {
              final t = await _showDrumTimePicker(context, _time);
              if (t != null) setState(() => _time = t);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: NeomeDesignSystem.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('시각', style: TextStyle(fontSize: 14)),
                  Text(
                    '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: NeomeDesignSystem.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            DateTime deadline;
            if (_useRelative) {
              deadline = widget.eventDate.subtract(Duration(days: _daysBefore));
            } else {
              deadline = _absoluteDate ?? widget.eventDate;
            }
            deadline = DateTime(
                deadline.year, deadline.month, deadline.day,
                _time.hour, _time.minute);
            Navigator.pop(context, _DeadlineResult(deadline));
          },
          style: FilledButton.styleFrom(
            backgroundColor: NeomeDesignSystem.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('설정'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Follow-up event dialog
// ─────────────────────────────────────────────────────────────
/// Shows "후속 일정 추가?" prompt. Returns follow-up date if user confirms, null otherwise.
Future<DateTime?> showFollowUpPrompt(BuildContext context, DateTime baseDate) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _FollowUpDialog(baseDate: baseDate),
  );
}

class _FollowUpDialog extends StatefulWidget {
  final DateTime baseDate;
  const _FollowUpDialog({required this.baseDate});

  @override
  State<_FollowUpDialog> createState() => _FollowUpDialogState();
}

class _FollowUpDialogState extends State<_FollowUpDialog> {
  bool _useRelative = true;
  int _daysAfter = 1;
  DateTime? _absoluteDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('후속 일정 추가',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이 일정의 후속 일정을 추가할까요?',
              style: TextStyle(fontSize: 14, color: NeomeDesignSystem.textSub)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _useRelative = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _useRelative
                          ? NeomeDesignSystem.primary
                          : NeomeDesignSystem.background,
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(10)),
                    ),
                    child: Center(
                      child: Text('+N일 후',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _useRelative
                                  ? Colors.white
                                  : NeomeDesignSystem.textSub)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _useRelative = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !_useRelative
                          ? NeomeDesignSystem.primary
                          : NeomeDesignSystem.background,
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(10)),
                    ),
                    child: Center(
                      child: Text('날짜 지정',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: !_useRelative
                                  ? Colors.white
                                  : NeomeDesignSystem.textSub)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_useRelative) ...[
            Row(
              children: [
                const Text('+', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(
                  width: 48,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      border: UnderlineInputBorder(),
                    ),
                    controller: TextEditingController(text: '$_daysAfter'),
                    onChanged: (v) => _daysAfter = int.tryParse(v) ?? 1,
                  ),
                ),
                const Text(' 일 후', style: TextStyle(fontSize: 14)),
              ],
            ),
          ] else ...[
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _absoluteDate ?? widget.baseDate.add(const Duration(days: 1)),
                  firstDate: widget.baseDate,
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _absoluteDate = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: NeomeDesignSystem.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _absoluteDate != null
                          ? DateFormat('yyyy년 M월 d일').format(_absoluteDate!)
                          : '날짜 선택',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('건너뜀',
              style: TextStyle(color: NeomeDesignSystem.textSub)),
        ),
        FilledButton(
          onPressed: () {
            DateTime followUpDate;
            if (_useRelative) {
              followUpDate = widget.baseDate.add(Duration(days: _daysAfter));
            } else {
              followUpDate = _absoluteDate ?? widget.baseDate.add(const Duration(days: 1));
            }
            Navigator.pop(context, followUpDate);
          },
          style: FilledButton.styleFrom(
            backgroundColor: NeomeDesignSystem.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('후속 추가'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small helper widgets
// ─────────────────────────────────────────────────────────────
class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? NeomeDesignSystem.primary.withOpacity(0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? NeomeDesignSystem.primary : NeomeDesignSystem.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? NeomeDesignSystem.primary
                    : NeomeDesignSystem.textSub),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? NeomeDesignSystem.primary
                    : NeomeDesignSystem.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final TimeOfDay? time;
  final VoidCallback onTap;

  const _TimeTile({required this.label, this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final display = time != null
        ? '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}'
        : '미설정';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: NeomeDesignSystem.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: NeomeDesignSystem.textHint)),
            const SizedBox(height: 4),
            Text(
              display,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: time != null
                    ? NeomeDesignSystem.textMain
                    : NeomeDesignSystem.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Internal data helpers
// ─────────────────────────────────────────────────────────────
class _ItemEntry {
  final String id = const Uuid().v4();
  final TextEditingController ctrl = TextEditingController();
  DateTime? deadline;

  void dispose() => ctrl.dispose();
}
