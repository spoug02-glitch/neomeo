// lib/features/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../data/prefs_service.dart';
import '../../data/place.dart';
import 'package:fl_location/fl_location.dart';
import '../../app/design_system.dart';
import '../../services/geofence_service_wrapper.dart';
import '../../services/geocoding_service.dart';

// initial → fetching → (confirmation sheet) → form
enum _LocationMode { initial, fetching, form }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // 0: Welcome
  // 1: 알람 권한
  // 2: 위치 권한
  // 3: 집 위치 설정
  // 4: Done
  int _step = 0;

  // ── Location step ──────────────────────────────────────────────────────────
  _LocationMode _locationMode = _LocationMode.initial;
  bool _isSaving = false;
  bool _showFetchAlternative = false;
  bool _isFetchingAddress = false; // 폼 내에서 주소 인식 중

  final _nameCtrl           = TextEditingController(text: '집');
  final _addressCtrl        = TextEditingController(); // 수동 주소 입력용
  final _detailedAddressCtrl = TextEditingController(); // 상세주소 입력용
  final _latCtrl            = TextEditingController();
  final _lonCtrl            = TextEditingController();
  final _nameFocusNode      = FocusNode();

  static const int _totalSteps = 3; // 알람 권한 / 위치 권한 / 집 위치 설정

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _detailedAddressCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  // ── 단계 이동 ──────────────────────────────────────────────────────────────

  void _goToStep(int step) => setState(() => _step = step);

  // ── 권한 ───────────────────────────────────────────────────────────────────

  Future<void> _requestNotificationPermission() async {
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
    setState(() => _step = 2);
  }

  /// Android 11+ 2단계 위치 권한 플로우
  Future<void> _requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      final bgStatus = await Permission.locationAlways.status;
      if (!bgStatus.isGranted && mounted) {
        await _showAlwaysAllowGuide();
      }
    }
    if (mounted) setState(() => _step = 3);
  }

  /// "항상 허용" 설정 앱 안내 다이얼로그
  Future<void> _showAlwaysAllowGuide() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('위치 "항상 허용" 설정'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '앱이 꺼진 상태에서도 집 이탈을 감지하려면\n"항상 허용"이 필요해요.\n',
            ),
            Text('설정 방법:', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('① [설정 열기] 버튼을 눌러주세요'),
            Text('② 화면에서 [권한] 선택'),
            Text('③ [위치] 선택'),
            Text('④ "항상 허용" 선택'),
            SizedBox(height: 10),
            Text(
              '경로: 앱 정보 › 권한 › 위치 › 항상 허용',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
  }

  // ── 위치 가져오기 ──────────────────────────────────────────────────────────

  Future<void> _fetchCurrentLocation() async {
    // initial / form 모두 폼 내 로딩 처리 — initial에서도 화면 전환 없이 버튼만 로딩
    final inForm = _locationMode == _LocationMode.form ||
        _locationMode == _LocationMode.initial;
    if (inForm) {
      setState(() => _isFetchingAddress = true);
    } else {
      setState(() {
        _locationMode = _LocationMode.fetching;
        _showFetchAlternative = false;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _locationMode == _LocationMode.fetching) {
          setState(() => _showFetchAlternative = true);
        }
      });
    }

    try {
      // GPS 서비스 활성화 확인 — 꺼져 있으면 안내
      final serviceEnabled = await FlLocation.isLocationServicesEnabled;
      if (!serviceEnabled) {
        if (!mounted) return;
        if (inForm) {
          setState(() => _isFetchingAddress = false);
        } else {
          setState(() => _locationMode = _LocationMode.form);
        }
        _showSnack('위치 서비스(GPS)가 꺼져 있어요. 설정에서 켜주세요.');
        return;
      }

      // 위치 권한 확인
      var locPermission = await FlLocation.checkLocationPermission();
      if (locPermission == LocationPermission.denied ||
          locPermission == LocationPermission.deniedForever) {
        locPermission = await FlLocation.requestLocationPermission();
        if (locPermission == LocationPermission.denied ||
            locPermission == LocationPermission.deniedForever) {
          if (!mounted) return;
          if (inForm) {
            setState(() => _isFetchingAddress = false);
          } else {
            setState(() => _locationMode = _LocationMode.form);
          }
          _showSnack('위치 권한이 필요해요. 설정에서 허용해주세요.');
          return;
        }
      }

      final location = await FlLocation.getLocation(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      if (!mounted) return;
      _latCtrl.text = location.latitude.toStringAsFixed(6);
      _lonCtrl.text = location.longitude.toStringAsFixed(6);

      final addr = await GeocodingService.reverseGeocode(
          location.latitude, location.longitude);
      if (addr != null && _addressCtrl.text.trim().isEmpty) {
        _addressCtrl.text = addr;
      }

      if (!mounted) return;
      if (inForm) {
        setState(() => _isFetchingAddress = false);
      } else {
        setState(() => _locationMode = _LocationMode.form);
      }

      // accuracy 필드: GPS 오차 반경(m). 50m 초과면 경고
      final acc = location.accuracy;
      if (acc != null && acc > 50) {
        _showSnack('GPS 정확도가 낮아요 (오차 ±${acc.toStringAsFixed(0)}m). 야외에서 다시 시도해보세요.');
      } else {
        _showSnack(addr != null ? '위치: $addr' : '좌표를 가져왔어요.');
      }
    } catch (e) {
      if (!mounted) return;
      if (inForm) {
        setState(() => _isFetchingAddress = false);
      } else {
        setState(() => _locationMode = _LocationMode.form);
      }
      _showSnack('위치를 가져오지 못했어요. 직접 입력해주세요.');
    }
  }

  void _cancelFetch() => setState(() {
        _locationMode = _LocationMode.initial;
        _showFetchAlternative = false;
      });

  void _useManualInput() => setState(() => _locationMode = _LocationMode.form);

  Future<void> _skipLocation() async {
    await PrefsService.markOnboardingDone();
    if (mounted) setState(() => _step = 4);
  }

  // ── 지도 확인 후 저장 ──────────────────────────────────────────────────────

  Future<void> _confirmAndSave() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());

    // 좌표가 없으면 바로 저장 시도 (유효성 검사는 _savePlace에서)
    if (lat == null || lon == null) {
      await _savePlace();
      return;
    }

    final result = await showDialog<LatLng>(
      context: context,
      builder: (ctx) => _LocationConfirmDialog(lat: lat, lon: lon),
    );

    if (result != null && mounted) {
      _latCtrl.text = result.latitude.toStringAsFixed(6);
      _lonCtrl.text = result.longitude.toStringAsFixed(6);
      await _savePlace();
    }
  }

  // ── 장소 저장 ──────────────────────────────────────────────────────────────

  Future<void> _savePlace() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('장소 이름을 입력해주세요.');
      return;
    }
    setState(() => _isSaving = true);

    final baseAddress = _addressCtrl.text.trim();
    final detail = _detailedAddressCtrl.text.trim();
    final fullAddress = [baseAddress, if (detail.isNotEmpty) detail]
        .where((s) => s.isNotEmpty)
        .join(' ');

    final newPlace = Place(
      id: const Uuid().v4(),
      name: name,
      address: fullAddress.isNotEmpty ? fullAddress : null,
      lat: double.tryParse(_latCtrl.text.trim()) ?? 0.0,
      lon: double.tryParse(_lonCtrl.text.trim()) ?? 0.0,
    );

    await PrefsService.savePlaces([newPlace]);
    await PrefsService.setActivePlaceId(newPlace.id);
    await GeofenceServiceWrapper().startMonitoringActivePlace();

    // 날씨/미세먼지 자동 활성화
    await PrefsService.setWeatherEnabled(true);
    await PrefsService.setDustEnabled(true);
    await PrefsService.markOnboardingDone();

    if (mounted) setState(() { _isSaving = false; _step = 4; }); // → Done
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeomeDesignSystem.background,
      body: SafeArea(
        child: Column(
          children: [
            if (_step > 0 && _step < 4) _buildProgressBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: _buildStepContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$_step / $_totalSteps',
                style: NeomeDesignSystem.caption.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _step / _totalSteps,
              minHeight: 4,
              backgroundColor: NeomeDesignSystem.border,
              color: NeomeDesignSystem.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0: return _buildWelcomeStep();
      case 1: return _buildPermissionStep();
      case 2: return _buildLocationPermStep();
      case 3: return _buildLocationStep();
      case 4: return _buildDoneStep();
      default: return const SizedBox();
    }
  }

  // ── Step 0: 환영 ───────────────────────────────────────────────────────────

  Widget _buildWelcomeStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const WindowLogo(size: 80),
        const SizedBox(height: 32),
        Text(
          '너머에 오신 것을 환영해요',
          style: NeomeDesignSystem.heading1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          '외출할 때 챙겨야 할 것들,\n혹시 빠뜨리진 않았을까 불안하셨나요?\n너머는 그 불안을 덜어주는 체크리스트 앱이에요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        _primaryButton('시작하기', () => _goToStep(1)),
      ],
    );
  }

  // ── Step 1: 알람 권한 ──────────────────────────────────────────────────────

  Widget _buildPermissionStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🔔', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 24),
        Text('알람 권한이 필요해요', style: NeomeDesignSystem.heading1, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          '알람은 너머의 핵심 기능이에요.\n체크리스트 알림을 받으려면 알람 권한이 꼭 필요해요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        _primaryButton('알람 권한 설정하기', _requestNotificationPermission),
      ],
    );
  }

  // ── Step 2: 위치 설정 ──────────────────────────────────────────────────────

  Widget _buildLocationStep() {
    switch (_locationMode) {
      case _LocationMode.initial:  return _buildLocationInitial();
      case _LocationMode.fetching: return _buildLocationFetching();
      case _LocationMode.form:     return _buildLocationForm();
    }
  }

  Widget _buildLocationPermStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('📍', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 24),
        Text('위치 권한이 필요해요', style: NeomeDesignSystem.heading1, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          '집을 나갈 때 알람을 받으려면 위치 권한이 필요해요.\n\n'
          '① 먼저 "앱 사용 중 허용"을 선택해주세요.\n'
          '② 이후 설정 화면에서 "항상 허용"으로\n'
          '   변경하면 앱이 꺼진 상태에서도 감지돼요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        _primaryButton('위치 권한 설정하기', _requestLocationPermission, icon: Icons.location_on),
      ],
    );
  }

  Widget _buildLocationInitial() {
    // 별도 "직접 설정하기" 전환 없이 폼을 바로 노출 —
    // 사용자가 첫 화면에서 바로 주소를 입력하거나 GPS로 자동 인식할 수 있음
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                const Text('🏠', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 16),
                Text('집 위치를 설정해주세요',
                    style: NeomeDesignSystem.heading1, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                // 두 버튼(GPS·직접입력)의 목적을 한 줄로 사전 안내
                const Text(
                  '외출 감지를 위해 집 위치를 알아야 해요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 주소 입력 카드 ──────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E8EB)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _textField(
                  controller: _nameCtrl,
                  focusNode: _nameFocusNode,
                  label: '장소 이름',
                  hint: '예: 집, 우리집',
                ),
                const SizedBox(height: 12),
                _textField(
                  controller: _addressCtrl,
                  label: '주소',
                  hint: '도로명 또는 지번 주소',
                ),
                const SizedBox(height: 12),
                _textField(
                  controller: _detailedAddressCtrl,
                  label: '상세 주소 (선택)',
                  hint: '동/호수, 층수 등',
                ),
                const SizedBox(height: 14),
                // GPS 자동 인식 버튼 — 주소 필드를 자동으로 채워줌
                OutlinedButton.icon(
                  onPressed: _isFetchingAddress ? null : _fetchCurrentLocation,
                  icon: _isFetchingAddress
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: NeomeDesignSystem.primary),
                        )
                      : const Icon(Icons.my_location, size: 18),
                  label: Text(_isFetchingAddress ? '위치 확인 중...' : '현재 위치 자동 인식'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    foregroundColor: NeomeDesignSystem.primary,
                    side: BorderSide(color: NeomeDesignSystem.primary.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _primaryButton('등록하고 시작하기',
              (_isSaving || _isFetchingAddress) ? null : _confirmAndSave,
              loading: _isSaving),
          const SizedBox(height: 12),
          _textButton('건너뛰기', (_isSaving || _isFetchingAddress) ? null : _skipLocation),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildLocationFetching() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 56, height: 56,
          child: CircularProgressIndicator(color: NeomeDesignSystem.primary, strokeWidth: 3),
        ),
        const SizedBox(height: 32),
        Text('현재 위치를 확인하고 있어요...', style: NeomeDesignSystem.heading2, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          '잠시만 기다려주세요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub, fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        AnimatedOpacity(
          opacity: _showFetchAlternative ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: _showFetchAlternative
              ? Column(children: [_outlinedButton('직접 설정하기', _useManualInput), const SizedBox(height: 12)])
              : const SizedBox(height: 64),
        ),
        _textButton('취소', _cancelFetch),
      ],
    );
  }

  Widget _buildLocationForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('집 위치를 설정해주세요', style: NeomeDesignSystem.heading1),
          const SizedBox(height: 8),
          Text('장소 정보를 입력하고 등록해주세요.', style: NeomeDesignSystem.body2),
          const SizedBox(height: 28),
          _textField(controller: _nameCtrl, focusNode: _nameFocusNode, label: '장소 이름', hint: '예: 집, 회사'),
          const SizedBox(height: 12),
          _textField(controller: _addressCtrl, label: '주소', hint: '도로명 또는 지번 주소'),
          const SizedBox(height: 12),
          _textField(controller: _detailedAddressCtrl, label: '상세 주소 (선택)', hint: '동/호수, 층수 등'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: (_isSaving || _isFetchingAddress) ? null : _fetchCurrentLocation,
            icon: _isFetchingAddress
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: NeomeDesignSystem.primary),
                  )
                : const Icon(Icons.my_location, size: 18),
            label: Text(_isFetchingAddress ? '위치 확인 중...' : '현재 위치 자동 인식'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: NeomeDesignSystem.primary,
              side: BorderSide(color: NeomeDesignSystem.primary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          _primaryButton('등록하고 시작하기', _isSaving ? null : _confirmAndSave, loading: _isSaving),
          const SizedBox(height: 12),
          _textButton('건너뛰기', _isSaving ? null : _skipLocation),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Step 3: 완료 ───────────────────────────────────────────────────────────

  Widget _buildDoneStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('✨', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 24),
        Text('준비가 됐어요!', style: NeomeDesignSystem.heading1, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          '이제 집을 나설 때 준비물을 잊지 않도록\n조용히 알림을 드릴게요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        _primaryButton('홈으로 가기', () => context.go('/home')),
      ],
    );
  }

  // ── 공통 위젯 ──────────────────────────────────────────────────────────────

  Widget _primaryButton(String label, VoidCallback? onPressed, {IconData? icon, bool loading = false}) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        child: loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : icon != null
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                    Text(label),
                  ])
                : Text(label),
      ),
    );
  }

  Widget _outlinedButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: NeomeDesignSystem.primary),
          foregroundColor: NeomeDesignSystem.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _textButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: NeomeDesignSystem.textSub),
        child: Text(label),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    FocusNode? focusNode,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      style: NeomeDesignSystem.body1,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          color: (focusNode?.hasFocus ?? false) ? NeomeDesignSystem.primary : NeomeDesignSystem.textHint,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NeomeDesignSystem.primary, width: 2),
        ),
      ),
    );
  }
}

// ── 위치 확인 다이얼로그 (지도 드래그로 핀 이동) ─────────────────────────────

class _LocationConfirmDialog extends StatefulWidget {
  final double lat;
  final double lon;
  const _LocationConfirmDialog({required this.lat, required this.lon});

  @override
  State<_LocationConfirmDialog> createState() => _LocationConfirmDialogState();
}

class _LocationConfirmDialogState extends State<_LocationConfirmDialog> {
  late LatLng _pinCenter;

  @override
  void initState() {
    super.initState();
    _pinCenter = LatLng(widget.lat, widget.lon);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 지도 + 고정 핀 (지도를 드래그하면 핀 위치 업데이트)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: _pinCenter,
                      initialZoom: 15,
                      onPositionChanged: (position, _) {
                        final center = position.center;
                        if (center != null) {
                          setState(() => _pinCenter = center);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.hyoni.neomeo',
                      ),
                    ],
                  ),
                  // 중앙 고정 핀 (지도가 움직이면 핀 끝이 항상 중심)
                  Transform.translate(
                    offset: const Offset(0, -24),
                    child: const Icon(
                      Icons.location_pin,
                      color: Color(0xFFEF4444),
                      size: 48,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 텍스트 + 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                const Text(
                  '여기가 집인가요?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_pinCenter.latitude.toStringAsFixed(5)}, ${_pinCenter.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 4),
                const Text(
                  '지도를 움직여 위치를 조정할 수 있어요',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          side: BorderSide(color: Colors.grey.shade300),
                          foregroundColor: NeomeDesignSystem.textSub,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('다시 입력'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _pinCenter),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: NeomeDesignSystem.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('맞아요'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
