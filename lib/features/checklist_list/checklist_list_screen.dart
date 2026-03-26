// lib/features/checklist_list/checklist_list_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/design_system.dart';
import '../../data/local_event.dart';
import '../../services/calendar_service.dart';

enum _FilterMode {
  place,    // 장소별 – GPS 연동 체크리스트
  dateBase, // 일자별 – 달력 일정 체크리스트
  once,     // 일회성
  recent,   // 최신순
  usage,    // 많이 사용한 순
  alpha,    // 가나다순
}

class ChecklistListScreen extends StatefulWidget {
  const ChecklistListScreen({super.key});

  @override
  State<ChecklistListScreen> createState() => _ChecklistListScreenState();
}

class _ChecklistListScreenState extends State<ChecklistListScreen> {
  final _service = CalendarService();
  List<LocalEvent> _all = [];
  _FilterMode _filter = _FilterMode.recent;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await _service.getAllLocalEvents();
    if (mounted) {
      setState(() {
        _all = events;
        _isLoading = false;
      });
    }
  }

  List<LocalEvent> get _filtered {
    List<LocalEvent> result;

    switch (_filter) {
      case _FilterMode.place:
        result = _all.where((e) => e.placeId != null || e.linkedChecklistType != null).toList();
      case _FilterMode.dateBase:
        result = _all.where((e) =>
            e.placeId == null &&
            e.linkedChecklistType == null &&
            e.repeatType != RepeatType.none).toList();
      case _FilterMode.once:
        result = _all.where((e) =>
            e.placeId == null &&
            e.linkedChecklistType == null &&
            e.repeatType == RepeatType.none).toList();
      case _FilterMode.recent:
        result = List.from(_all)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _FilterMode.usage:
        result = List.from(_all)
          ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
      case _FilterMode.alpha:
        result = List.from(_all)
          ..sort((a, b) => a.title.compareTo(b.title));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeomeDesignSystem.background,
      appBar: AppBar(
        title: const Text('리스트', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const NeomeBottomNav(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterChips(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    const chips = [
      (_FilterMode.recent,   '최신순'),
      (_FilterMode.place,    '장소별'),
      (_FilterMode.dateBase, '일자별'),
      (_FilterMode.once,     '일회성'),
      (_FilterMode.usage,    '많이 사용한 순'),
      (_FilterMode.alpha,    '가나다순'),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((chip) {
            final mode = chip.$1;
            final label = chip.$2;
            final selected = _filter == mode;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filter = mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? NeomeDesignSystem.primary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? NeomeDesignSystem.primary
                          : NeomeDesignSystem.border,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : NeomeDesignSystem.textSub,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildList() {
    final items = _filtered;

    // 장소별 필터: 자동 생성 "집 나갈 때" 카드도 맨 위에 보여줌
    final showAutoCard = _filter == _FilterMode.place || _filter == _FilterMode.recent;

    if (items.isEmpty && !showAutoCard) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist, size: 48, color: NeomeDesignSystem.textHint.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              '체크리스트가 없어요',
              style: NeomeDesignSystem.body2.copyWith(color: NeomeDesignSystem.textHint),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: NeomeDesignSystem.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: items.length + (showAutoCard ? 1 : 0),
        itemBuilder: (context, index) {
          // Auto-generated "집 나갈 때" GPS checklist card
          if (showAutoCard && index == 0) {
            return _AutoChecklistCard(
              onTap: () => context.push('/checklist?type=${Uri.encodeComponent('나갈때')}'),
            );
          }
          final event = items[showAutoCard ? index - 1 : index];
          return _EventChecklistCard(
            event: event,
            onTap: () => context.push('/checklist?type=${Uri.encodeComponent(event.title)}'),
          );
        },
      ),
    );
  }
}

// ── 자동 생성 GPS 체크리스트 카드 ─────────────────────────────
class _AutoChecklistCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AutoChecklistCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NeomeDesignSystem.primary.withOpacity(0.3)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NeomeDesignSystem.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on_outlined,
                color: NeomeDesignSystem.primary, size: 22),
          ),
          title: const Text(
            '집 나갈 때',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: const Text(
            'GPS 자동 연동 · 집을 나설 때 알림',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
}

// ── 일반 이벤트 체크리스트 카드 ──────────────────────────────
class _EventChecklistCard extends StatelessWidget {
  final LocalEvent event;
  final VoidCallback onTap;

  const _EventChecklistCard({required this.event, required this.onTap});

  Color get _importanceColor {
    switch (event.importance) {
      case EventImportance.high:   return const Color(0xFFF97316);
      case EventImportance.medium: return const Color(0xFF22C55E);
      case EventImportance.none:   return const Color(0xFF94A3B8);
    }
  }

  String get _repeatLabel {
    switch (event.repeatType) {
      case RepeatType.none:        return '';
      case RepeatType.daily:       return event.repeatExcludeWeekends ? '매일(영업일)' : '매일';
      case RepeatType.weeklyDays:  return '매주 선택';
      case RepeatType.weekly:      return '매주';
      case RepeatType.monthly:     return '매달';
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('M/d HH:mm').format(event.startTime);
    final total = event.checklistItems.length;
    final done  = event.checklistItems.where((i) => i.checked).length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NeomeDesignSystem.border),
        ),
        child: Row(
          children: [
            // Importance bar
            Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                color: _importanceColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (_repeatLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: NeomeDesignSystem.background,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _repeatLabel,
                              style: const TextStyle(
                                fontSize: 10,
                                color: NeomeDesignSystem.textSub,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          timeStr,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                        if (total > 0) ...[
                          const Text('  ·  ', style: TextStyle(color: Color(0xFF94A3B8))),
                          Text(
                            '$done/$total 완료',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ],
                    ),
                    if (total > 0) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: done / total,
                          minHeight: 3,
                          backgroundColor: NeomeDesignSystem.border,
                          valueColor: AlwaysStoppedAnimation(_importanceColor),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: NeomeDesignSystem.textHint, size: 20),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
