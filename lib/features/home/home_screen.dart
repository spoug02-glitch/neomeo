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
  int _precipPct = 0;
  bool _isSnow = false;
  int _aqiValue = 0;

  @override
  void initState() {
    super.initState();
    _checkHomeSet();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    final apiKey = await PrefsService.getWeatherApiKey();
    final activePlace = await PrefsService.getActivePlace();
    final weatherEnabled = await PrefsService.isWeatherEnabled();
    final dustEnabled = await PrefsService.isDustEnabled();

    if (apiKey.isEmpty || activePlace == null) {
      if (mounted) setState(() => _isLoadingWeather = false);
      return;
    }

    try {
      final weather = await WeatherService.fetchWeather(activePlace.lat, activePlace.lon, apiKey);
      final forecast = await WeatherService.fetchForecast(activePlace.lat, activePlace.lon, apiKey);
      final sensitivity = await PrefsService.getTempSensitivity();

      String rec = '';
      int precipPct = 0;
      bool isSnow = false;

      if (forecast != null && forecast.isNotEmpty) {
        final next12h = forecast.take(4).toList();
        final temps = next12h.map((e) => (e['main']['temp'] as num).toDouble()).toList();
        final avgTemp = temps.reduce((a, b) => a + b) / temps.length;
        final minTemp = temps.reduce((a, b) => a < b ? a : b);
        final maxTemp = temps.reduce((a, b) => a > b ? a : b);

        final adjustedAvg = avgTemp + sensitivity;
        final baseClothing = WeatherService.getSimpleClothing(adjustedAvg);
        final tempDiff = maxTemp - minTemp;

        if (tempDiff >= 8) {
          rec = '$baseClothing + 가디건 (기온: ${minTemp.toStringAsFixed(0)}°~${maxTemp.toStringAsFixed(0)}°)';
        } else {
          rec = '$baseClothing (기온: ${minTemp.toStringAsFixed(0)}°~${maxTemp.toStringAsFixed(0)}°)';
        }

        precipPct = WeatherService.getMaxPrecipProb(forecast);
        isSnow = WeatherService.isSnowExpected(forecast);
      }

      final airData = await WeatherService.fetchAirPollution(activePlace.lat, activePlace.lon, apiKey);
      final aqiValue = WeatherService.getAqiValue(airData);

      if (mounted) {
        setState(() {
          _currentWeather = weather;
          _clothingRec = rec;
          _umbrellaRec = weatherEnabled && WeatherService.shouldBringUmbrella(weather);
          _maskRec = dustEnabled && WeatherService.shouldWearMask(airData);
          _precipPct = precipPct;
          _isSnow = isSnow;
          _aqiValue = aqiValue;
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
                    if (_isLoadingWeather)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_currentWeather != null)
                      _WeatherCard(
                        temp: (_currentWeather!['main']['temp'] as num).toDouble(),
                        description: _currentWeather!['weather'][0]['description'],
                        iconCode: _currentWeather!['weather'][0]['icon'],
                        clothingRec: _clothingRec,
                        umbrellaRec: _umbrellaRec,
                        maskRec: _maskRec,
                        precipPct: _precipPct,
                        isSnow: _isSnow,
                        aqiValue: _aqiValue,
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

// ── WeatherCard ─────────────────────────────────────────────

class _WeatherCard extends StatelessWidget {
  final double temp;
  final String description;
  final String iconCode;
  final String clothingRec;
  final bool umbrellaRec;
  final bool maskRec;
  final int precipPct;
  final bool isSnow;
  final int aqiValue;

  const _WeatherCard({
    required this.temp,
    required this.description,
    required this.iconCode,
    required this.clothingRec,
    required this.umbrellaRec,
    required this.maskRec,
    required this.precipPct,
    required this.isSnow,
    required this.aqiValue,
  });

  Color _precipColor() {
    if (precipPct >= 60) return const Color(0xFF1565C0);
    if (precipPct >= 30) return const Color(0xFF42A5F5);
    return const Color(0xFF94A3B8);
  }

  Color _aqiColor() {
    switch (aqiValue) {
      case 1: return const Color(0xFF4CAF50);
      case 2: return const Color(0xFF2196F3);
      case 3: return const Color(0xFFFFC107);
      case 4: return const Color(0xFFFF9800);
      case 5: return const Color(0xFFF44336);
      default: return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final precipLabel = isSnow ? '눈·비 확률' : '강수확률';
    final aqiLabel = WeatherService.getAqiLabel(aqiValue);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 상단: 날씨(좌) + 2셀 그리드(우) ──────────────
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 좌: 아이콘 + 온도 + 설명
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Text(
                          _weatherEmoji(iconCode),
                          style: const TextStyle(fontSize: 48),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${temp.toStringAsFixed(1)}°C',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 세로 구분선
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: const Color(0xFFE5E8EB),
                  ),

                  // 우: 위(강수확률) / 아래(미세먼지)
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        // 위: 강수확률
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  precipLabel,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$precipPct%',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: _precipColor(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 가로 구분선
                        Container(height: 1, color: const Color(0xFFE5E8EB)),
                        // 아래: 미세먼지
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '미세먼지',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  aqiValue == 0 ? '-' : aqiLabel,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _aqiColor(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 옷차림 추천 ──────────────────────────────────
            if (clothingRec.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: NeomeDesignSystem.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.checkroom,
                        size: 15, color: NeomeDesignSystem.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '오늘의 추천 옷차림: $clothingRec',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── 준비물 추천 (조건부) ──────────────────────────
            if (umbrellaRec || maskRec) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.backpack_outlined,
                      size: 15, color: NeomeDesignSystem.primary),
                  const SizedBox(width: 6),
                  const Text(
                    '준비물',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (umbrellaRec) _chip('☂', '우산'),
                  if (umbrellaRec && maskRec) const SizedBox(width: 6),
                  if (maskRec) _chip('😷', '마스크'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _weatherEmoji(String code) {
    switch (code.replaceFirst('n', 'd')) {
      case '01d': return '☀️';
      case '02d': return '🌤️';
      case '03d': return '⛅';
      case '04d': return '☁️';
      case '09d': return '🌧️';
      case '10d': return '🌦️';
      case '11d': return '⛈️';
      case '13d': return '❄️';
      case '50d': return '🌫️';
      default:    return '🌡️';
    }
  }

  Widget _chip(String emoji, String label) {
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

// ── ChecklistCard ────────────────────────────────────────────

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
