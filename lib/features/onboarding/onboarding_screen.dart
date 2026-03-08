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
  // 0: Welcome
  // 1: Permissions
  // 2: AlarmMode ("시간" vs "위치")
  // 3: TimeAlarm (시간 선택) OR Location (위치 설정) — _alarmMode에 따라 분기
  // 4: PrepTime (준비 시작 시간)
  // 5: Done
  int _step = 0;

  // ── AlarmMode ──────────────────────────────────────────────────────────────
  String? _alarmMode; // 'time' | 'location'

  // ── TimeAlarm ──────────────────────────────────────────────────────────────
  String _alarmTime = '08:00';

  // ── Location step ──────────────────────────────────────────────────────────
  _LocationMode _locationMode = _LocationMode.initial;
  bool _isSaving = false;
  bool _showFetchAlternative = false;

  final _nameCtrl    = TextEditingController(text: '집');
  final _addressCtrl = TextEditingController();
  final _latCtrl     = TextEditingController();
  final _lonCtrl     = TextEditingController();
  final _nameFocusNode = FocusNode();

  // ── PrepTime ───────────────────────────────────────────────────────────────
  String _prepTime = '07:30';

  // 프로그레스 바를 표시하는 마지막 step (Done 직전)
  static const int _totalSteps = 5;

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

  /// 위치/시간 설정을 건너뛰고 PrepTime으로 이동
  void _skipToPrep() => setState(() => _step = 4);

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

  // ── AlarmMode 선택 ─────────────────────────────────────────────────────────

  Future<void> _selectAlarmMode(String mode) async {
    await PrefsService.setAlarmMode(mode); // UT 카운터 누적 포함
    setState(() {
      _alarmMode = mode;
      _step = 3;
    });
  }

  // ── TimeAlarm ──────────────────────────────────────────────────────────────

  Future<void> _pickAlarmTime() async {
    final parts = _alarmTime.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (picked != null) {
      setState(() {
        _alarmTime =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _saveAlarmTime() async {
    await PrefsService.setAlarmTime(_alarmTime);
    _skipToPrep();
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

    if (mounted) setState(() { _isSaving = false; _step = 4; });
  }

  // ── PrepTime ───────────────────────────────────────────────────────────────

  static const _timePresets = [
    '06:00', '06:30', '07:00', '07:30', '08:00', '08:30', '09:00',
  ];

  Future<void> _pickPrepTime() async {
    final parts = _prepTime.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (picked != null) {
      setState(() {
        _prepTime =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _savePrepTime() async {
    await PrefsService.setPrepTime(_prepTime);
    await PrefsService.markOnboardingDone();
    if (mounted) setState(() => _step = 5);
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
            if (_step < 5) _buildProgressBar(),
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
      case 2: return _buildAlarmModeStep();
      case 3: return _alarmMode == 'time'
          ? _buildTimeAlarmStep()
          : _buildLocationStep();
      case 4: return _buildPrepTimeStep();
      case 5: return _buildDoneStep();
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
        Text('권한 설정이 필요해요', style: NeomeDesignSystem.heading1, textAlign: TextAlign.center),
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

  // ── Step 2: 알람 방식 선택 ─────────────────────────────────────────────────

  Widget _buildAlarmModeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('🔔', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 20),
        Text('알람은 언제 나오는 게 좋으세요?', style: NeomeDesignSystem.heading1),
        const SizedBox(height: 8),
        Text(
          '어떤 방식이 더 편하신지 골라주세요.',
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const SizedBox(height: 36),
        _AlarmModeCard(
          emoji: '⏰',
          title: '시간',
          subtitle: '매일 정해진 시간에 알림을 받아요',
          onTap: () => _selectAlarmMode('time'),
        ),
        const SizedBox(height: 14),
        _AlarmModeCard(
          emoji: '📍',
          title: '위치',
          subtitle: '집을 나설 때 자동으로 알림을 받아요',
          onTap: () => _selectAlarmMode('location'),
        ),
        const Spacer(),
        _textButton('나중에 할게요', _skipToPrep),
      ],
    );
  }

  // ── Step 3-A: 시간 알람 설정 ───────────────────────────────────────────────

  static const _alarmPresets = [
    '06:00', '06:30', '07:00', '07:30', '08:00', '08:30', '09:00',
  ];

  Widget _buildTimeAlarmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('⏰', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 20),
        Text('언제 체크리스트 알람을 드릴까요?', style: NeomeDesignSystem.heading1),
        const SizedBox(height: 8),
        Text(
          '매일 이 시간에 외출 준비 알림을 보내드려요.',
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub,
            fontWeight: FontWeight.normal,
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: GestureDetector(
            onTap: _pickAlarmTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: NeomeDesignSystem.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NeomeDesignSystem.primary, width: 1.5),
              ),
              child: Text(
                _alarmTime,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: NeomeDesignSystem.primary,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: _alarmPresets.map((t) {
            final selected = t == _alarmTime;
            return ChoiceChip(
              label: Text(t),
              selected: selected,
              onSelected: (_) => setState(() => _alarmTime = t),
              selectedColor: NeomeDesignSystem.primary,
              labelStyle: TextStyle(
                color: selected ? Colors.white : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
              backgroundColor: const Color(0xFFF1F5F9),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _pickAlarmTime,
            icon: const Icon(Icons.access_time, size: 16),
            label: const Text('직접 선택'),
            style: TextButton.styleFrom(foregroundColor: NeomeDesignSystem.textSub),
          ),
        ),
        const Spacer(),
        _primaryButton('다음', _saveAlarmTime),
        const SizedBox(height: 12),
        _textButton('나중에 설정할게요', _skipToPrep),
      ],
    );
  }

  // ── Step 3-B: 위치 설정 ────────────────────────────────────────────────────

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
        Text('집 위치를 설정해주세요', style: NeomeDesignSystem.heading1, textAlign: TextAlign.center),
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
        _primaryButton('현재 위치 가져오기', _fetchCurrentLocation, icon: Icons.my_location),
        const SizedBox(height: 12),
        _outlinedButton('직접 설정하기', _useManualInput),
        const SizedBox(height: 12),
        _textButton('나중에 할게요', _skipToPrep),
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
          const SizedBox(height: 12),
          _textButton('나중에 할게요', _isSaving ? null : _skipToPrep),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Step 4: 준비 시작 시간 ─────────────────────────────────────────────────

  Widget _buildPrepTimeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('⏰', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 20),
        Text('외출 준비는 언제 시작하세요?', style: NeomeDesignSystem.heading1),
        const SizedBox(height: 8),
        Text(
          '이 시간에 맞춰 준비할 수 있도록 도와드려요.',
          style: NeomeDesignSystem.body1.copyWith(
            color: NeomeDesignSystem.textSub, fontWeight: FontWeight.normal,
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: GestureDetector(
            onTap: _pickPrepTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: NeomeDesignSystem.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NeomeDesignSystem.primary, width: 1.5),
              ),
              child: Text(
                _prepTime,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: NeomeDesignSystem.primary,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: _timePresets.map((t) {
            final selected = t == _prepTime;
            return ChoiceChip(
              label: Text(t),
              selected: selected,
              onSelected: (_) => setState(() => _prepTime = t),
              selectedColor: NeomeDesignSystem.primary,
              labelStyle: TextStyle(
                color: selected ? Colors.white : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
              backgroundColor: const Color(0xFFF1F5F9),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _pickPrepTime,
            icon: const Icon(Icons.access_time, size: 16),
            label: const Text('직접 선택'),
            style: TextButton.styleFrom(foregroundColor: NeomeDesignSystem.textSub),
          ),
        ),
        const Spacer(),
        _primaryButton('다음', _savePrepTime),
        const SizedBox(height: 12),
        _textButton('나중에 설정할게요', () async {
          await PrefsService.markOnboardingDone();
          if (mounted) setState(() => _step = 5);
        }),
      ],
    );
  }

  // ── Step 5: 완료 ───────────────────────────────────────────────────────────

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

// ── AlarmMode 선택 카드 ────────────────────────────────────────────────────────

class _AlarmModeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AlarmModeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }
}
