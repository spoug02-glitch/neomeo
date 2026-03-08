// lib/features/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../data/prefs_service.dart';
import '../../data/place.dart';
import 'package:fl_location/fl_location.dart';
import '../../app/design_system.dart';
import '../../services/geofence_service_wrapper.dart';

enum _LocationMode { initial, fetching, form }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0: Welcome, 1: Permissions, 2: Location, 3: Done

  // Location step sub-state
  _LocationMode _locationMode = _LocationMode.initial;
  bool _isSaving = false;
  bool _showFetchAlternative = false; // 위치 로딩 중 일정 시간 후 대체 버튼 표시

  // Form controllers
  final _nameCtrl = TextEditingController(text: '집');
  final _addressCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _nameFocusNode = FocusNode();

  static const int _totalSteps = 3;

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

  Future<void> _skipOnboarding() async {
    await PrefsService.markOnboardingDone();
    if (mounted) context.go('/home');
  }

  // ── 권한 ───────────────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
    _goToStep(2);
  }

  // ── 위치 가져오기 ──────────────────────────────────────────────────────────

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _locationMode = _LocationMode.fetching;
      _showFetchAlternative = false;
    });

    // 3초 후 "직접 설정하기" 대체 버튼 노출
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _locationMode == _LocationMode.fetching) {
        setState(() => _showFetchAlternative = true);
      }
    });

    try {
      // 먼저 마지막 알려진 위치 시도 (빠름)
      Location? location;
      try {
        location = await FlLocation.getLocation(
          accuracy: LocationAccuracy.low,
        );
      } catch (_) {
        // 빠른 위치 실패 시 일반 요청으로 fallback
      }

      // 빠른 위치 실패 시 높은 정확도로 재시도
      location ??= await FlLocation.getLocation(
        accuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      _latCtrl.text = location!.latitude.toStringAsFixed(6);
      _lonCtrl.text = location.longitude.toStringAsFixed(6);
      setState(() => _locationMode = _LocationMode.form);
      _showSnack('현재 위치를 가져왔어요!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationMode = _LocationMode.form);
      _showSnack('위치를 가져오지 못했어요. 직접 입력하거나 나중에 설정해주세요.');
    }
  }

  void _cancelFetch() {
    setState(() {
      _locationMode = _LocationMode.initial;
      _showFetchAlternative = false;
    });
  }

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
    await PrefsService.markOnboardingDone();

    if (mounted) setState(() { _isSaving = false; _step = 3; });
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
          '집이나 회사를 나설 때,\n챙겨야 할 준비물을 잊지 않도록 도와드려요.',
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

  // ── Step 1: 권한 ───────────────────────────────────────────────────────────

  Widget _buildPermissionStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('📍', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 24),
        Text(
          '권한 설정이 필요해요',
          style: NeomeDesignSystem.heading1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          '외출 감지와 알림을 위해 위치 권한과 알림 권한이 필요해요.\n나중에 설정에서도 변경할 수 있어요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        _primaryButton('권한 허용하기', _requestPermissions),
        const SizedBox(height: 12),
        _textButton('나중에 할게요', () => _goToStep(2)),
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

  Widget _buildLocationInitial() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('🏠', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 24),
        Text(
          '집 위치를 설정해주세요',
          style: NeomeDesignSystem.heading1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          '외출 감지를 위해 집 위치를 알아야 해요.\n지금 바로 설정하거나 나중에 하실 수 있어요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        _primaryButton(
          '현재 위치 가져오기',
          _fetchCurrentLocation,
          icon: Icons.my_location,
        ),
        const SizedBox(height: 12),
        _outlinedButton('직접 설정하기', _useManualInput),
        const SizedBox(height: 12),
        _textButton('나중에 할게요', _skipOnboarding),
      ],
    );
  }

  Widget _buildLocationFetching() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            color: NeomeDesignSystem.primary,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          '현재 위치를 확인하고 있어요...',
          style: NeomeDesignSystem.heading2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          '잠시만 기다려주세요.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),
        AnimatedOpacity(
          opacity: _showFetchAlternative ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: _showFetchAlternative
              ? Column(
                  children: [
                    _outlinedButton('직접 설정하기', _useManualInput),
                    const SizedBox(height: 12),
                  ],
                )
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
          _textField(
            controller: _nameCtrl,
            focusNode: _nameFocusNode,
            label: '장소 이름',
            hint: '예: 집, 회사',
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _addressCtrl,
            label: '주소 (선택)',
            hint: '도로명 또는 지번 주소',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _latCtrl,
                  label: '위도',
                  hint: '37.123456',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  controller: _lonCtrl,
                  label: '경도',
                  hint: '127.123456',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _isSaving ? null : _fetchCurrentLocation,
            icon: const Icon(Icons.my_location, size: 16),
            label: const Text('현재 위치 자동 인식'),
            style: TextButton.styleFrom(foregroundColor: NeomeDesignSystem.primary),
          ),
          const SizedBox(height: 24),
          _primaryButton(
            '등록하고 시작하기',
            _isSaving ? null : _savePlace,
            loading: _isSaving,
          ),
          const SizedBox(height: 12),
          _textButton('나중에 할게요', _isSaving ? null : _skipOnboarding),
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

  Widget _primaryButton(
    String label,
    VoidCallback? onPressed, {
    IconData? icon,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : icon != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18),
                      const SizedBox(width: 8),
                      Text(label),
                    ],
                  )
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
          color: (focusNode?.hasFocus ?? false)
              ? NeomeDesignSystem.primary
              : NeomeDesignSystem.textHint,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NeomeDesignSystem.primary, width: 2),
        ),
      ),
    );
  }
}
