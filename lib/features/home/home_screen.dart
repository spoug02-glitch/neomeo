// lib/features/home/home_screen.dart
//
// Mirrors the web index.html home screen:
//   • 너머 title + sub
//   • Outing type grid (출근, 운동, 약속, 직접 추가)
//   • Bottom nav: 홈 | 설정


import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/design_system.dart';
import '../../services/geofence_service_wrapper.dart';
import '../../services/weather_service.dart';
import '../../services/calendar_service.dart';
import '../../data/prefs_service.dart';
import '../../data/place.dart';

const _outingTypes = [
  ('출근', '🏢'),
  ('운동', '🏃'),
  ('약속', '🤝'),
  ('회의', '💼'),
  ('직접 추가', '✏️'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _homeSet = false;
  Map<String, dynamic>? _currentWeather;
  String _clothingRec = '';
  bool _isLoadingWeather = true;
  final CalendarService _calendarService = CalendarService();
  String? _suggestedType;
  bool _isCalendarSynced = false;

  @override
  void initState() {
    super.initState();
    _checkHomeSet();
    _loadWeather();
    _checkCalendar();
  }

  Future<void> _checkCalendar() async {
    final events = await _calendarService.getTodayEvents();
    if (events.isNotEmpty) {
      final now = DateTime.now();
      // Find the next upcoming event
      final nextEvent = events.where((e) {
        final start = e.start?.dateTime ?? e.start?.date;
        return start != null && start.isAfter(now);
      }).firstOrNull ?? events.first;

      setState(() {
        _suggestedType = _calendarService.classifyEvent(nextEvent);
        _isCalendarSynced = true;
      });
    }
  }

  Future<void> _syncCalendar() async {
    final user = await _calendarService.signIn();
    if (user != null) {
      await _checkCalendar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('캘린더 일정을 성공적으로 가져왔습니다.')),
        );
      }
    }
  }

  Future<void> _loadWeather() async {
    final apiKey = await PrefsService.getWeatherApiKey();
    final activePlace = await PrefsService.getActivePlace();
    final weatherEnabled = await PrefsService.isWeatherEnabled();

    if (apiKey.isEmpty || activePlace == null || !weatherEnabled) {
      if (mounted) setState(() => _isLoadingWeather = false);
      return;
    }

    try {
      final weather = await WeatherService.fetchWeather(activePlace.lat, activePlace.lon, apiKey);
      final forecast = await WeatherService.fetchForecast(activePlace.lat, activePlace.lon, apiKey);
      final sensitivity = await PrefsService.getTempSensitivity();

      String rec = '';
      if (forecast != null && forecast.isNotEmpty) {
        // Calculate average temp for next 12 hours (4 forecast items, each 3h)
        final next12h = forecast.take(4).toList();
        final temps = next12h.map((e) => (e['main']['temp'] as num).toDouble()).toList();
        final avgTemp = temps.reduce((a, b) => a + b) / temps.length;
        final minTemp = temps.reduce((a, b) => a < b ? a : b);
        final maxTemp = temps.reduce((a, b) => a > b ? a : b);

        final adjustedAvg = avgTemp + sensitivity;
        rec = WeatherService.calculateRecommendedClothes(adjustedAvg);
        
        // Add variability suggestion
        if (maxTemp - minTemp >= 8) {
          rec = '$rec + 가디건이나 겉옷 (일교차 대비)';
        }

        rec = '$rec (기온: ${minTemp.toStringAsFixed(0)}°~${maxTemp.toStringAsFixed(0)}°)';
      }

      if (mounted) {
        setState(() {
          _currentWeather = weather;
          _clothingRec = rec;
          _isLoadingWeather = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  Future<void> _checkHomeSet() async {
    final set = await 
    GeofenceServiceWrapper.isHomeSet();
    if (mounted) setState(() => _homeSet = set);
  }

  void _onOutingTap(String type, String emoji) {
    if (type == '직접 추가') {
      _showCustomTypeDialog();
      return;
    }
    context.go('/checklist?type=${Uri.encodeComponent(type)}');
  }

  Future<void> _showCustomTypeDialog() async {
    String custom = '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('외출 종류 입력'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 병원, 쇼핑'),
          onChanged: (v) => custom = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, custom),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      context.go('/checklist?type=${Uri.encodeComponent(result.trim())}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header ────────────────────────────────
                    Column(
                      children: [
                        const WindowLogo(size: 48),
                        const SizedBox(height: 16),
                        Text(
                          '너머',
                          textAlign: TextAlign.center,
                          style: NeomeDesignSystem.heading1.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '외출 전, 조용히 안심을 더해요',
                          textAlign: TextAlign.center,
                          style: NeomeDesignSystem.body2,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Weather & Clothing Recommendation ──────
                    if (!_isLoadingWeather && _currentWeather != null)
                      _WeatherCard(
                        temp: (_currentWeather!['main']['temp'] as num).toDouble(),
                        description: _currentWeather!['weather'][0]['description'],
                        iconCode: _currentWeather!['weather'][0]['icon'],
                        clothingRec: _clothingRec,
                      ),
                    if (!_isLoadingWeather && _currentWeather != null) const SizedBox(height: 16),

                     // ── Geofence setup card ───────────────────
                    if (!_homeSet)
                      _GeofenceSetupBanner(
                        onTap: () async {
                          await context.push('/permission-setup');
                          _checkHomeSet();
                        },
                      ),
                    
                    const SizedBox(height: 16),

                    // ── Calendar Sync Banner ──────────────────
                    if (_isCalendarSynced && _suggestedType != null)
                      _CalendarSuggestionBanner(
                        type: _suggestedType!,
                        onTap: () => _onOutingTap(_suggestedType!, ''),
                      ),

                    const SizedBox(height: 16),

                    // ── Outing type selection ─────────────────
                    _OutingCard(onTap: _onOutingTap),
                  ],
                ),
              ),
            ),
            _BottomNav(currentIndex: 0),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────

class _GeofenceSetupBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _GeofenceSetupBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: NeomeDesignSystem.primary.withOpacity(0.05),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: const Text(
          '집 위치를 등록하면 외출 시 알려드려요',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: NeomeDesignSystem.primary,
          ),
        ),
        subtitle: Text(
          '지금 설정하기 →',
          style: TextStyle(fontSize: 13, color: NeomeDesignSystem.primary.withOpacity(0.7)),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  final double temp;
  final String description;
  final String iconCode;
  final String clothingRec;

  const _WeatherCard({
    required this.temp,
    required this.description,
    required this.iconCode,
    required this.clothingRec,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Image.network(
                  'https://openweathermap.org/img/wn/$iconCode@2x.png',
                  width: 50,
                  height: 50,
                  errorBuilder: (_, __, ___) => const Icon(Icons.wb_sunny_outlined, size: 40, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${temp.toStringAsFixed(1)}°C',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                    ),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ),
            if (clothingRec.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                children: [
                   const Icon(Icons.checkroom, size: 18, color: Color(0xFF6366F1)),
                   const SizedBox(width: 8),
                   Expanded(
                     child: Text(
                       '오늘의 옷차림: $clothingRec',
                       style: const TextStyle(
                         fontSize: 13,
                         fontWeight: FontWeight.w600,
                         color: Color(0xFF475569),
                       ),
                     ),
                   ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OutingCard extends StatelessWidget {
  final void Function(String type, String emoji) onTap;
  const _OutingCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '지금 어디 가세요?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/settings'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFF94A3B8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('알람 설정'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.5,
              children: _outingTypes
                  .map((t) => _OutingTile(
                        emoji: t.$2,
                        label: t.$1,
                        onTap: () => onTap(t.$1, t.$2),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutingTile extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  const _OutingTile({required this.emoji, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const Spacer(),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  const _BottomNav({required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: NeomeDesignSystem.border, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) {
          if (i == 0) context.go('/home');
          if (i == 1) context.go('/settings');
          if (i == 2) context.go('/calendar');
        },
        backgroundColor: Colors.white,
        selectedItemColor: NeomeDesignSystem.primary,
        unselectedItemColor: NeomeDesignSystem.textSub,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: '설정'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), activeIcon: Icon(Icons.calendar_month), label: '달력'),
        ],
      ),
    );
  }
}



class _CalendarSuggestionBanner extends StatelessWidget {
  final String type;
  final VoidCallback onTap;
  const _CalendarSuggestionBanner({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: NeomeDesignSystem.primary,
      child: ListTile(
        leading: const Icon(Icons.auto_awesome, color: Colors.white),
        title: Text(
          '다음 일정은 "$type"인가요?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          '탭하여 바로 체크리스트 확인하기 →',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        onTap: onTap,
      ),
    );
  }
}
