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

// locationPerm → initial → fetching → (confirmation sheet) → form
enum _LocationMode { locationPerm, initial, fetching, form }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // 0: Welcome
  // 1: Permissions (알람)
  // 2: Location
  // 3: Done
  int _step = 0;

  // ── Location step ──────────────────────────────────────────────────────────
  _LocationMode _locationMode = _LocationMode.locationPerm;
  bool _isSaving = false;
  bool _showFetchAlternative = false;

  final _nameCtrl    = TextEditingController(text: '집');
  final _addressCtrl = TextEditingController();
  final _latCtrl     = TextEditingController();
  final _lonCtrl     = TextEditingController();
  final _nameFocusNode = FocusNode();

  static const int _totalSteps = 3; // Welcome / 알람 / 위치

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
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
    setState(() {
      _step = 2;
      _locationMode = _LocationMode.locationPerm;
    });
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
    if (mounted) setState(() => _locationMode = _LocationMode.initial);
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
    setState(() {
      _locationMode = _LocationMode.fetching;
      _showFetchAlternative = false;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _locationMode == _LocationMode.fetching) {
        setState(() => _showFetchAlternative = true);
      }
    });

    try {
      Location? location;
      try {
        location = await FlLocation.getLocation(accuracy: LocationAccuracy.low);
      } catch (_) {}

      location ??= await FlLocation.getLocation(accuracy: LocationAccuracy.high);

      if (!mounted) return;

      final lat = location.latitude;
      final lon = location.longitude;
      _latCtrl.text = lat.toStringAsFixed(6);
      _lonCtrl.text = lon.toStringAsFixed(6);

      // fetching 표시 종료 후 확인 시트 표시
      setState(() => _locationMode = _LocationMode.initial);

      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _LocationConfirmBottomSheet(lat: lat, lon: lon),
      );

      if (confirmed == true && mounted) {
        await _savePlace();
      }
      // confirmed == false 또는 닫힘 → initial 상태 유지
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationMode = _LocationMode.form);
      _showSnack('위치를 가져오지 못했어요. 직접 입력해주세요.');
    }
  }

  void _cancelFetch() => setState(() {
        _locationMode = _LocationMode.initial;
        _showFetchAlternative = false;
      });

  void _useManualInput() => setState(() => _locationMode = _LocationMode.form);

  // ── 장소 저장 ──────────────────────────────────────────────────────────────

  Future<void> _savePlace() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('장소 이름을 입력해주세요.');
      return;
    }
    setState(() => _isSaving = true);

    final newPlace = Place(
      id: const Uuid().v4(),
      name: name,
      address: _addressCtrl.text.trim().isNotEmpty ? _addressCtrl.text.trim() : null,
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

    if (mounted) setState(() { _isSaving = false; _step = 3; }); // → Done
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
            if (_step < 3) _buildProgressBar(),
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
                '${_step + 1} / $_totalSteps',
                style: NeomeDesignSystem.caption.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_step + 1) / _totalSteps,
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
      case 2: return _buildLocationStep();
      case 3: return _buildDoneStep();
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
      case _LocationMode.locationPerm: return _buildLocationPermStep();
      case _LocationMode.initial:      return _buildLocationInitial();
      case _LocationMode.fetching:     return _buildLocationFetching();
      case _LocationMode.form:         return _buildLocationForm();
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🏠', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 24),
        Text('집 위치를 설정해주세요', style: NeomeDesignSystem.heading1, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          '외출 감지를 위해 집 위치를 알아야 해요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        _primaryButton('현재 위치 확인', _fetchCurrentLocation, icon: Icons.my_location),
        const SizedBox(height: 12),
        _outlinedButton('직접 설정하기', _useManualInput),
      ],
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
          const SizedBox(height: 16),
          _textField(controller: _addressCtrl, label: '주소 (선택)', hint: '도로명 또는 지번 주소'),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _isSaving ? null : _fetchCurrentLocation,
            icon: const Icon(Icons.my_location, size: 16),
            label: const Text('현재 위치 자동 인식'),
            style: TextButton.styleFrom(foregroundColor: NeomeDesignSystem.primary),
          ),
          const SizedBox(height: 24),
          _primaryButton('등록하고 시작하기', _isSaving ? null : _savePlace, loading: _isSaving),
          const SizedBox(height: 16),
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

// ── 위치 확인 바텀시트 ─────────────────────────────────────────────────────────

class _LocationConfirmBottomSheet extends StatelessWidget {
  final double lat;
  final double lon;

  const _LocationConfirmBottomSheet({required this.lat, required this.lon});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 드래그 핸들
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '여기가 집인가요?',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            // 지도
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 260,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lon),
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.hyoni.neomeo',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lon),
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.location_pin,
                            color: Color(0xFFEF4444),
                            size: 48,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      side: BorderSide(color: Colors.grey.shade300),
                      foregroundColor: NeomeDesignSystem.textSub,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('다시 가져오기'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: NeomeDesignSystem.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('맞아요'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
