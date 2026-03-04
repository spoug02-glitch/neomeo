import 'package:flutter/material.dart';
import '../../app/design_system.dart';
import '../../services/calendar_service.dart';
import 'package:googleapis/calendar/v3.dart' as gCal;

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final CalendarService _calendarService = CalendarService();
  List<gCal.Event> _events = [];
  bool _isLoading = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _refreshEvents();
  }

  Future<void> _refreshEvents() async {
    setState(() => _isLoading = true);
    final events = await _calendarService.getTodayEvents();
    setState(() {
      _events = events;
      _isLoading = false;
      _isLoggedIn = events.isNotEmpty || _isLoggedIn; // Simplistic check
    });
  }

  Future<void> _handleSignIn() async {
    final user = await _calendarService.signIn();
    if (user != null) {
      _refreshEvents();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeomeDesignSystem.background,
      appBar: AppBar(
        title: const Text('오늘의 일정', style: NeomeDesignSystem.heading2),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const NeomeBottomNav(currentIndex: 2),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddEventDialog,
        backgroundColor: NeomeDesignSystem.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_events.isEmpty)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 64, color: NeomeDesignSystem.textSub),
                      const SizedBox(height: 16),
                      const Text(
                        '오늘의 일정이 없습니다',
                        style: NeomeDesignSystem.body1,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '새 일정을 추가하거나\n구글 캘린더를 연동해 보세요.',
                        textAlign: TextAlign.center,
                        style: NeomeDesignSystem.body2,
                      ),
                      const SizedBox(height: 24),
                      if (!_isLoggedIn)
                        OutlinedButton(
                          onPressed: _handleSignIn,
                          child: const Text('구글 캘린더 연동하기'),
                        ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final category = _calendarService.classifyEvent(event);
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(
                            event.summary ?? '제목 없음',
                            style: NeomeDesignSystem.body1.copyWith(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '${event.start?.dateTime?.toLocal().toIso8601String().substring(11, 16) ?? "시간 미정"} - ${category}',
                                style: NeomeDesignSystem.body2,
                              ),
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: NeomeDesignSystem.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              category,
                              style: const TextStyle(
                                color: NeomeDesignSystem.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddEventDialog() async {
    String summary = '';
    TimeOfDay selectedTime = TimeOfDay.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('새 일정 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: '일정 제목', hintText: '예: 미팅, 운동'),
                onChanged: (v) => summary = v,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('시간 설정'),
                trailing: Text(selectedTime.format(context)),
                onTap: () async {
                  final time = await showTimePicker(context: context, initialTime: selectedTime);
                  if (time != null) setState(() => selectedTime = time);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(
              onPressed: () {
                if (summary.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final now = DateTime.now();
      final startTime = DateTime(now.year, now.month, now.day, selectedTime.hour, selectedTime.minute);
      await _calendarService.saveLocalEvent(summary, startTime);
      _refreshEvents();
    }
  }
}

