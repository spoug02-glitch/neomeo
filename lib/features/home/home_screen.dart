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
  String? _activePlaceId;
  Map<String, dynamic>? _currentWeather;
  String _clothingRec = '';
  bool _isLoadingWeather = true;
  String _windInfo = '';
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
    // 로컬 prefs 병렬 로드
    final prefResults = await Future.wait([
      PrefsService.getWeatherApiKey(),
      PrefsService.getActivePlace(),
      PrefsService.isWeatherEnabled(),
      PrefsService.isDustEnabled(),
      PrefsService.getTempSensitivity(),
    ]);
    final apiKey        = prefResults[0] as String;
    final activePlace   = prefResults[1] as Place?;
    final weatherEnabled = prefResults[2] as bool;
    final dustEnabled   = prefResults[3] as bool;
    final sensitivity   = prefResults[4] as double;

    if (apiKey.isEmpty || activePlace == null) {
      if (mounted) setState(() => _isLoadingWeather = false);
      return;
    }

    try {
      // 3개 API 병렬 호출
      final apiResults = await Future.wait([
        WeatherService.fetchWeather(activePlace.lat, activePlace.lon, apiKey),
        WeatherService.fetchForecast(activePlace.lat, activePlace.lon, apiKey),
        WeatherService.fetchAirPollution(activePlace.lat, activePlace.lon, apiKey),
      ]);
      final weather  = apiResults[0] as Map<String, dynamic>?;
      final forecast = apiResults[1] as List<dynamic>?;
      final airData  = apiResults[2] as Map<String, dynamic>?;

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
          rec = '$baseClothing + 가디건 (예보: ${minTemp.toStringAsFixed(0)}°~${maxTemp.toStringAsFixed(0)}°)';
        } else {
          rec = '$baseClothing (예보: ${minTemp.toStringAsFixed(0)}°~${maxTemp.toStringAsFixed(0)}°)';
        }

        precipPct = WeatherService.getMaxPrecipProb(forecast);
        isSnow = WeatherService.isSnowExpected(forecast);
      }

      final aqiValue = WeatherService.getAqiValue(airData);

      if (mounted) {
        setState(() {
          _currentWeather = weather;
          _clothingRec = rec;
          _windInfo = WeatherService.getWindInfo(weather);
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
    final activePlace = await PrefsService.getActivePlace();
    if (mounted) setState(() {
      _homeSet = set;
      _activePlaceId = activePlace?.id;
    });
  }

  Future<void> _saveCurrentLocationAsHome() async {
    setState(() => _isSavingLocation = true);
    debugPrint('[UT] 현재 위치 저장 시도...');
    try {
      final loc = await FlLocation.getLocation(accuracy: LocationAccuracy.high);

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
        setState(() { _homeSet = true; _isSavingLocation = false; _activePlaceId = place.id; });
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

  void _onHomeOutingTap() {
    context.go('/checklist?type=${Uri.encodeComponent('외출')}');
  }

  // 시간대별 미세 인사 — 앱의 배려하는 동반자 톤앤매너 강화
  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 7)  return '이른 아침도 함께할게요 🌙';
    if (hour < 12) return '오늘 하루도 잘 준비해봐요 ☀️';
    if (hour < 18) return '외출 전 잠깐, 함께 확인해봐요';
    return '저녁 외출도 꼼꼼하게 챙겨봐요 🌙';
  }

  // 하단 고정 CTA 영역 —
  // 집 위치 미설정 시 회색 보조 버튼(방해 없는 존재감),
  // 메인 CTA는 항상 노출해 단 하나의 행동으로 시선을 유도
  Widget _buildBottomCTA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        children: [
          if (!_homeSet) ...[
            // 회색 OutlinedButton — 필수가 아닌 보조 액션임을 시각적으로 전달
            OutlinedButton.icon(
              onPressed: _isSavingLocation ? null : _saveCurrentLocationAsHome,
              icon: _isSavingLocation
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF94A3B8)),
                    )
                  : const Icon(Icons.home_outlined, size: 18),
              label: Text(_isSavingLocation ? '위치 확인 중...' : '현재 위치를 집으로 설정'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: const Color(0xFF94A3B8),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 메인 CTA — 화면의 시각적 무게 중심을 하단으로 유도
          FilledButton.icon(
            onPressed: _onHomeOutingTap,
            icon: const Icon(Icons.checklist_rtl_outlined, size: 20),
            label: const Text('외출 준비 시작하기'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: NeomeDesignSystem.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                        const SizedBox(height: 4),
                        // 시간대별 미세 인사로 배려하는 동반자 느낌 부여
                        Text(
                          _timeGreeting(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
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
                    else if (_currentWeather != null) ...[
                      _WeatherCard(
                        temp: (_currentWeather!['main']['temp'] as num).toDouble(),
                        windInfo: _windInfo,
                        iconCode: _currentWeather!['weather'][0]['icon'],
                        precipPct: _precipPct,
                        isSnow: _isSnow,
                        aqiValue: _aqiValue,
                      ),
                      const SizedBox(height: 12),
                      // ── 오늘의 추천 카드 ─────────────────────
                      _TodayRecommendCard(
                        clothingRec: _clothingRec,
                        umbrellaRec: _umbrellaRec,
                        maskRec: _maskRec,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 집 위치 버튼·CTA는 하단 고정 영역(_buildBottomCTA)으로 이동
                    // 스크롤 콘텐츠는 날씨·추천 정보에 집중

                  ],
                ),
              ),
            ),
            // 회색 보조 버튼(집 위치) + 메인 CTA — 탭바 바로 위 고정
            _buildBottomCTA(),
            const NeomeBottomNav(currentIndex: 0),
          ],
        ),
      ),
    )); // PopScope
  }
}

// ── WeatherCard ─────────────────────────────────────────────

class _WeatherCard extends StatelessWidget {
  final double temp;
  final String windInfo;
  final String iconCode;
  final int precipPct;
  final bool isSnow;
  final int aqiValue;

  const _WeatherCard({
    required this.temp,
    required this.windInfo,
    required this.iconCode,
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
                            if (windInfo.isNotEmpty)
                              Text(
                                windInfo,
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
}

// ── TodayRecommendCard ────────────────────────────────────────

class _TodayRecommendCard extends StatelessWidget {
  final String clothingRec;
  final bool umbrellaRec;
  final bool maskRec;

  const _TodayRecommendCard({
    required this.clothingRec,
    required this.umbrellaRec,
    required this.maskRec,
  });

  @override
  Widget build(BuildContext context) {
    final itemsText = umbrellaRec && maskRec
        ? '☂ 우산, 😷 마스크'
        : umbrellaRec
            ? '☂ 우산'
            : maskRec
                ? '😷 마스크'
                : '😊 웃음';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '오늘의 추천',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            _row(Icons.checkroom_outlined, '옷차림', clothingRec.isNotEmpty ? clothingRec : '-'),
            const SizedBox(height: 8),
            _row(Icons.backpack_outlined, '준비물', itemsText),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: NeomeDesignSystem.primary),
        const SizedBox(width: 6),
        Text(
          '$label :',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }
}

// ── ChecklistCard ────────────────────────────────────────────

class _ChecklistCard extends StatelessWidget {
  final VoidCallback onTap;
  final String emoji;
  final String title;
  final String subtitle;
  final String? settingsPlaceId;

  const _ChecklistCard({
    required this.onTap,
    this.emoji = '🎒',
    this.title = '외출할 때',
    this.subtitle = '체크리스트 확인하기',
    this.settingsPlaceId,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InkWell(
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
                Text(emoji, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
        if (settingsPlaceId != null)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push(
                  '/checklist-settings?placeId=$settingsPlaceId&type=${Uri.encodeComponent('외출')}',
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
