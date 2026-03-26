// lib/features/calendar/calendar_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gCal;
import '../../app/design_system.dart';
import '../../data/local_event.dart';
import '../../data/prefs_service.dart';
import '../../services/calendar_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final CalendarService _calendarService = CalendarService();

  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  List<LocalEvent> _localEvents = [];
  List<gCal.Event> _googleEvents = [];
  bool _isLoading = false;

  // active place depart trigger days: DateTime.weekday format (1=월,...,7=일)
  Set<int> _checklistWeekdays = {};

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _refreshEvents();
  }

  Future<void> _loadStatus() async {
    final place = await PrefsService.getActivePlace();

    Set<int> checklistWeekdays = {};
    if (place != null) {
      final days =
          await PrefsService.getChecklistTriggerDaysFor(place.id, 'depart');
      // prefs: 0=일,1=월,...,6=토 → DateTime.weekday: 1=월,...,7=일
      checklistWeekdays = days.map((d) => d == 0 ? 7 : d).toSet();
    }

    if (mounted) {
      setState(() => _checklistWeekdays = checklistWeekdays);
    }
  }

  Future<void> _refreshEvents() async {
    setState(() => _isLoading = true);

    final localEvents =
        await _calendarService.getLocalEventsForDay(_selectedDate);

    List<gCal.Event> googleEvents = [];
    if (_isToday(_selectedDate)) {
      googleEvents = await _calendarService.getGoogleEventsToday();
    }

    if (mounted) {
      setState(() {
        _localEvents = localEvents;
        _googleEvents = googleEvents;
        _isLoading = false;
      });
    }
  }

  // ── Date helpers ───────────────────────────────────────────
  List<DateTime> _daysInMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);

    // Sunday-first: 일월화수목금토
    // DateTime.weekday: 1=Mon,...,7=Sun
    // We need Sun=0 prefix, so shift: prefixDays = (first.weekday % 7)
    final prefixDays = first.weekday % 7; // Mon→1, ..., Sat→6, Sun→0

    final days = <DateTime>[];
    for (int i = prefixDays; i > 0; i--) {
      days.add(first.subtract(Duration(days: i)));
    }
    for (int i = 0; i < last.day; i++) {
      days.add(DateTime(month.year, month.month, i + 1));
    }
    while (days.length % 7 != 0) {
      days.add(
          last.add(Duration(days: days.length - prefixDays - last.day + 1)));
    }
    return days;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) => _isSameDay(d, DateTime.now());

  bool _isInFocusedMonth(DateTime d) =>
      d.month == _focusedMonth.month && d.year == _focusedMonth.year;

  void _goToPrevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      _selectedDate =
          DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    });
    _refreshEvents();
  }

  void _goToNextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      _selectedDate =
          DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    });
    _refreshEvents();
  }

  // ── Add event (추후 공개 예정) ─────────────────────────────
  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('일정 추가 기능은 추후 공개 예정이에요'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: NeomeDesignSystem.textMain,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeomeDesignSystem.background,
      appBar: AppBar(
        title: const Text('달력',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const NeomeBottomNav(currentIndex: 2),
      floatingActionButton: FloatingActionButton(
        onPressed: _showComingSoon,
        backgroundColor: NeomeDesignSystem.textHint,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMonthHeader(),
              const SizedBox(height: 12),
              _buildWeekdayHeader(),
              const SizedBox(height: 4),
              _buildCalendarGrid(),
              const SizedBox(height: 20),
              _buildEventList(),
            ],
          ),
        ),
      ),
    );
  }

  // ── 월 헤더 ────────────────────────────────────────────────
  Widget _buildMonthHeader() {
    final title = DateFormat('yyyy년 M월').format(_focusedMonth);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: _goToPrevMonth,
          icon: const Icon(Icons.chevron_left,
              color: NeomeDesignSystem.textMain),
          splashRadius: 20,
        ),
        Text(title, style: NeomeDesignSystem.heading2),
        IconButton(
          onPressed: _goToNextMonth,
          icon: const Icon(Icons.chevron_right,
              color: NeomeDesignSystem.textMain),
          splashRadius: 20,
        ),
      ],
    );
  }

  // ── 요일 헤더: 일월화수목금토 ─────────────────────────────
  Widget _buildWeekdayHeader() {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return Row(
      children: days.map((d) {
        final color = d == '일'
            ? const Color(0xFFEF4444)
            : d == '토'
                ? const Color(0xFF3B82F6)
                : NeomeDesignSystem.textHint;
        return Expanded(
          child: Center(
            child: Text(
              d,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 달력 그리드 ────────────────────────────────────────────
  Widget _buildCalendarGrid() {
    final days = _daysInMonth(_focusedMonth);
    final rows = <Widget>[];

    for (int i = 0; i < days.length; i += 7) {
      final week = days.sublist(i, i + 7);
      rows.add(Row(children: week.map(_buildDayCell).toList()));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NeomeDesignSystem.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(children: rows),
    );
  }

  Widget _buildDayCell(DateTime d) {
    final inMonth = _isInFocusedMonth(d);
    final today = _isToday(d);
    final selected = _isSameDay(d, _selectedDate);
    final hasChecklist = inMonth &&
        _checklistWeekdays.isNotEmpty &&
        _checklistWeekdays.contains(d.weekday);

    // Sunday in day grid: index 0 → weekday==7 in DateTime
    final isSunday = d.weekday == 7;
    final isSaturday = d.weekday == 6;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedDate = d);
          _refreshEvents();
        },
        child: Container(
          height: 50,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected
                ? NeomeDesignSystem.primary
                : today
                    ? NeomeDesignSystem.primary.withOpacity(0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${d.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected || today ? FontWeight.w700 : FontWeight.normal,
                  color: selected
                      ? Colors.white
                      : !inMonth
                          ? NeomeDesignSystem.textHint.withOpacity(0.4)
                          : isSunday
                              ? const Color(0xFFEF4444)
                              : isSaturday
                                  ? const Color(0xFF3B82F6)
                                  : NeomeDesignSystem.textMain,
                ),
              ),
              if (hasChecklist)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? Colors.white.withOpacity(0.8)
                        : NeomeDesignSystem.primary.withOpacity(0.6),
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  // ── 체크리스트 자동 카드 ──────────────────────────────────
  Widget _buildChecklistAutoCard() {
    return GestureDetector(
      onTap: () =>
          context.push('/checklist?type=${Uri.encodeComponent('나갈때')}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: NeomeDesignSystem.primary.withOpacity(0.2)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: NeomeDesignSystem.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          title: const Text(
            '외출 체크리스트',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: const Text(
            '집 나갈 때 알림이 예정되어 있어요',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          trailing: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: NeomeDesignSystem.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '자동',
              style: TextStyle(
                color: NeomeDesignSystem.primary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 선택 날짜 일정 리스트 ──────────────────────────────────
  Widget _buildEventList() {
    final dateLabel = _isToday(_selectedDate)
        ? '오늘의 일정'
        : DateFormat('M월 d일 (E)', 'ko_KR').format(_selectedDate);

    final isChecklistDay = _checklistWeekdays.isNotEmpty &&
        _checklistWeekdays.contains(_selectedDate.weekday);

    final hasAny = _localEvents.isNotEmpty || _googleEvents.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            dateLabel,
            style:
                NeomeDesignSystem.body1.copyWith(fontWeight: FontWeight.w700),
          ),
        ),

        // Checklist auto card
        if (!_isLoading && isChecklistDay) _buildChecklistAutoCard(),

        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (!hasAny && !isChecklistDay)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NeomeDesignSystem.border),
            ),
            child: Column(
              children: [
                Icon(Icons.event_note_outlined,
                    size: 40,
                    color: NeomeDesignSystem.textHint.withOpacity(0.5)),
                const SizedBox(height: 10),
                Text(
                  '일정이 없어요',
                  style: NeomeDesignSystem.body2.copyWith(
                      color: NeomeDesignSystem.textHint),
                ),
                const SizedBox(height: 4),
                const Text(
                  '+ 버튼으로 일정을 추가해 보세요',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          )
        else ...[
          // Local events
          ..._localEvents.map(_buildLocalEventCard),
          // Google events
          ..._googleEvents.map(_buildGoogleEventCard),
        ],
      ],
    );
  }

  // ── Local event card ───────────────────────────────────────
  Widget _buildLocalEventCard(LocalEvent event) {
    final Color barColor;
    switch (event.importance) {
      case EventImportance.high:
        barColor = const Color(0xFFF97316);
      case EventImportance.medium:
        barColor = const Color(0xFF22C55E);
      case EventImportance.none:
        barColor = const Color(0xFF94A3B8);
    }

    final timeStr = DateFormat('HH:mm').format(event.startTime);
    final endStr = event.endTime != null
        ? ' – ${DateFormat('HH:mm').format(event.endTime!)}'
        : '';

    final total = event.checklistItems.length;
    final done = event.checklistItems.where((i) => i.checked).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NeomeDesignSystem.border),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$timeStr$endStr'
                    '${total > 0 ? '  ·  $done/$total 완료' : ''}',
                    style: NeomeDesignSystem.caption,
                  ),
                  if (total > 0 && event.isChecklistMode) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: done / total,
                        minHeight: 3,
                        backgroundColor: NeomeDesignSystem.border,
                        valueColor: AlwaysStoppedAnimation(barColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Google Calendar event card ─────────────────────────────
  Widget _buildGoogleEventCard(gCal.Event event) {
    final timeStr = event.start?.dateTime?.toLocal() != null
        ? DateFormat('HH:mm').format(event.start!.dateTime!.toLocal())
        : '시간 미정';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NeomeDesignSystem.border),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF4285F4), // Google blue
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(
          event.summary ?? '제목 없음',
          style: NeomeDesignSystem.body1
              .copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$timeStr  ·  Google 캘린더',
          style: NeomeDesignSystem.caption,
        ),
      ),
    );
  }
}
