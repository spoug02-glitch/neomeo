// lib/features/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_location/fl_location.dart';
import 'package:uuid/uuid.dart';
import '../../app/design_system.dart';
import '../../services/geofence_service_wrapper.dart';
import '../../services/weather_service.dart';
import '../../data/prefs_service.dart';
import '../../data/place.dart';
import '../../utils/recommendation_service.dart';

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
  bool _umbrellaRec = false;
  bool _maskRec = false;
  bool _isSavingLocation = false;
  List<String> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _checkHomeSet();
    _loadWeather();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    final recs = await RecommendationService.getTodayRecommendations();
    if (mounted) setState(() => _recommendations = recs);
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
        final next12h = forecast.take(4).toList();
        final temps = next12h.map((e) => (e['main']['temp'] as num).toDouble()).toList();
        final avgTemp = temps.reduce((a, b) => a + b) / temps.length;
        final minTemp = temps.reduce((a, b) => a < b ? a : b);
        final maxTemp = temps.reduce((a, b) => a > b ? a : b);

        final adjustedAvg = avgTemp + sensitivity;
        rec = WeatherService.calculateRecommendedClothes(adjustedAvg);

        if (maxTemp - minTemp >= 8) {
          rec = '$rec + 가디건이나 겉옷 (일교차 대비)';
        }
        rec = '$rec (기온: ${minTemp.toStringAsFixed(0)}°~${maxTemp.toStringAsFixed(0)}°)';
      }

      final airData = await WeatherService.fetchAirPollution(activePlace.lat, activePlace.lon, apiKey);

      if (mounted) {
        setState(() {
          _currentWeather = weather;
          _clothingRec = rec;
          _umbrellaRec = WeatherService.shouldBringUmbrella(weather);
          _maskRec = WeatherService.shouldWearMask(airData);
          _isLoadingWeather = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  Future<void> _checkHomeSet() async {
    final set = await GeofenceServiceWrapper.isHomeSet();
    if (mounted) setState(() => _homeSet = set);
  }

  /// 현재 위치를 기준 위치(집)로 저장하고 지오펜스 모니터링 시작
  Future<void> _saveCurrentLocationAsHome() async {
    setState(() => _isSavingLocation = true);
    debugPrint('[UT] 현재 위치 저장 시도...');
    try {
      Location? loc;
      try {
        loc = await FlLocation.getLocation(accuracy: LocationAccuracy.low);
      } catch (_) {}
      loc ??= await FlLocation.getLocation(accuracy: LocationAccuracy.high);

      final place = Place(
        id: const Uuid().v4(),
        name: '집',
        lat: loc.latitude,
        lon: loc.longitude,
      );
      await PrefsService.savePlaces([place]);
      await PrefsService.setActivePlaceId(place.id);
      await GeofenceServiceWrapper().startMonitoringActivePlace();

      debugPrint('[UT] 위치 저장 완료 — lat=${loc.latitude} lon=${loc.longitude}');

      if (mounted) {
        setState(() { _homeSet = true; _isSavingLocation = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('기준 위치가 설정되었습니다. 이 위치를 벗어나면 알려드릴게요.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[UT] 위치 저장 실패: $e');
      if (mounted) {
        setState(() => _isSavingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치를 가져오지 못했어요. 위치 권한을 확인해주세요.')),
        );
      }
    }
  }

  void _onOutingTap() {
    context.go('/checklist?type=${Uri.encodeComponent('등교')}');
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

                    // ── Weather Card ──────────────────────────
                    if (!_isLoadingWeather && _currentWeather != null)
                      _WeatherCard(
                        temp: (_currentWeather!['main']['temp'] as num).toDouble(),
                        description: _currentWeather!['weather'][0]['description'],
                        iconCode: _currentWeather!['weather'][0]['icon'],
                        clothingRec: _clothingRec,
                        umbrellaRec: _umbrellaRec,
                        maskRec: _maskRec,
                      ),
                    if (!_isLoadingWeather && _currentWeather != null)
                      const SizedBox(height: 16),

                    // ── 집 위치 설정 버튼 (미설정 시) ──────────────
                    if (!_homeSet) ...[
                      FilledButton.icon(
                        onPressed: _isSavingLocation ? null : _saveCurrentLocationAsHome,
                        icon: _isSavingLocation
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.home_outlined),
                        label: Text(_isSavingLocation ? '위치 확인 중...' : '현재 위치를 집으로 설정'),
                        style: FilledButton.styleFrom(
                          backgroundColor: NeomeDesignSystem.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '집을 나설 때 자동으로 알려드려요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── 오늘의 추천템 카드 ────────────────────────
                    if (_recommendations.isNotEmpty) ...[
                      _TodayRecommendationCard(recommendations: _recommendations),
                      const SizedBox(height: 16),
                    ],

                    // ── 등교 체크리스트 카드 ──────────────────────
                    _ChecklistCard(onTap: _onOutingTap),
                  ],
                ),
              ),
            ),
            const NeomeBottomNav(currentIndex: 0),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────

class _TodayRecommendationCard extends StatelessWidget {
  final List<String> recommendations;
  const _TodayRecommendationCard({required this.recommendations});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tips_and_updates_outlined,
                    size: 18, color: NeomeDesignSystem.primary),
                const SizedBox(width: 8),
                const Text(
                  '오늘의 추천템',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...recommendations.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      RecommendationService.emojiFor(item),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$item 챙기세요',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ChecklistCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const Text('🎒', style: TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '등교',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '체크리스트 확인하기',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  final double temp;
  final String description;
  final String iconCode;
  final String clothingRec;
  final bool umbrellaRec;
  final bool maskRec;

  const _WeatherCard({
    required this.temp,
    required this.description,
    required this.iconCode,
    required this.clothingRec,
    required this.umbrellaRec,
    required this.maskRec,
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
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.wb_sunny_outlined, size: 40, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${temp.toStringAsFixed(1)}°C',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
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
                  const Icon(Icons.checkroom, size: 18, color: NeomeDesignSystem.primary),
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
            if (umbrellaRec || maskRec) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.backpack_outlined, size: 16, color: NeomeDesignSystem.primary),
                  const SizedBox(width: 6),
                  const Text(
                    '추천 준비물',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                  ),
                  const SizedBox(width: 10),
                  if (umbrellaRec)
                    _RecommendChip(emoji: '☂', label: '우산'),
                  if (umbrellaRec && maskRec) const SizedBox(width: 8),
                  if (maskRec)
                    _RecommendChip(emoji: '😷', label: '마스크'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _RecommendChip extends StatelessWidget {
  final String emoji;
  final String label;
  const _RecommendChip({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: NeomeDesignSystem.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NeomeDesignSystem.primary.withOpacity(0.2)),
      ),
      child: Text(
        '$emoji $label',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: NeomeDesignSystem.primary,
        ),
      ),
    );
  }
}
