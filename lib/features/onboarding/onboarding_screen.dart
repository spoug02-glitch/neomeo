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

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0: Welcome, 1: Permissions, 2: Location Input, 3: Done
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _detailedAddressCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  bool _isSaving = false;
  final _nameFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(() {
      setState(() {}); // Update color on focus
    });
  }

  Future<void> _requestPermissions() async {
    // Request location
    var status = await Permission.location.request();
    if (!status.isGranted) {
      _showError('위치 권한이 필요합니다.');
      return;
    }

    // Request notification
    await Permission.notification.request();

    // Request battery optimization exemption
    await Permission.ignoreBatteryOptimizations.request();

    setState(() => _step = 2);
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isSaving = true);
    try {
      final location = await FlLocation.getLocation();
      setState(() {
        _latCtrl.text = location.latitude.toString();
        _lonCtrl.text = location.longitude.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('현재 위치의 좌표를 성공적으로 가져왔습니다.')));
    } catch (e) {
      _showError('위치를 가져오지 못했습니다: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveInitialPlace() async {
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final detailedAddress = _detailedAddressCtrl.text.trim();
    final lat = double.tryParse(_latCtrl.text.trim()) ?? 0.0;
    final lon = double.tryParse(_lonCtrl.text.trim()) ?? 0.0;

    if (name.isEmpty) {
      _showError('장소 이름을 입력해주세요.');
      return;
    }

    setState(() => _isSaving = true);

    final newPlace = Place(
      id: const Uuid().v4(),
      name: name,
      address: address.isNotEmpty ? address : null,
      detailedAddress: detailedAddress.isNotEmpty ? detailedAddress : null,
      lat: lat,
      lon: lon,
    );

    await PrefsService.savePlaces([newPlace]);
    await PrefsService.setActivePlaceId(newPlace.id);
    await GeofenceServiceWrapper().startMonitoringActivePlace();
    await PrefsService.markOnboardingDone();

    setState(() {
      _isSaving = false;
      _step = 3;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeomeDesignSystem.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _buildStepContents(),
        ),
      ),
    );
  }

  Widget _buildStepContents() {
    switch (_step) {
      case 0:
        return _buildWelcomeStep();
      case 1:
        return _buildPermissionStep();
      case 2:
        return _buildLocationStep();
      case 3:
        return _buildDoneStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildWelcomeStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const WindowLogo(size: 80),
        const SizedBox(height: 32),
        Text(
          '너머에 오신 것을 환영합니다',
          style: NeomeDesignSystem.heading1,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          '너머는 집이나 회사를 나설 때\n깜빡하기 쉬운 준비물을 챙기도록 도와줍니다.',
          textAlign: TextAlign.center,
          style: NeomeDesignSystem.body1.copyWith(color: NeomeDesignSystem.textSub, fontWeight: FontWeight.normal),
        ),
        const Spacer(),
        FilledButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text('시작하기'),
        ),
      ],
    );
  }

  Widget _buildPermissionStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('📍', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 24),
        const Text(
          '권한 설정이 필요합니다',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          '외출을 감지하기 위해 위치 권한과\n알림 권한이 필요합니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: _requestPermissions,
            child: const Text('권한 허용하기'),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            '첫 번째 장소를 등록할까요?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '집이나 회사 등 자주 나가는 곳을 입력해주세요.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameCtrl,
            focusNode: _nameFocusNode,
            style: NeomeDesignSystem.body1,
            decoration: InputDecoration(
              labelText: '장소 이름',
              labelStyle: TextStyle(
                color: _nameFocusNode.hasFocus ? NeomeDesignSystem.primary : NeomeDesignSystem.textHint,
              ),
              hintText: '예: 우리집, 회사',
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
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(
              labelText: '주소',
              hintText: '도로명 주소 또는 지번 주소',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _detailedAddressCtrl,
            decoration: const InputDecoration(
              labelText: '상세 주소',
              hintText: '동, 호수 등',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _getCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('현재 위치 가져오기'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _isSaving ? null : _saveInitialPlace,
              child: _isSaving
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('장소 등록 및 완료'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('✨', style: TextStyle(fontSize: 60)),
        const SizedBox(height: 24),
        const Text(
          '준비가 끝났습니다!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          '이제 해당 장소를 나설 때 알림을 보내드릴게요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: () => context.go('/home'),
            child: const Text('홈으로 이동'),
          ),
        ),
      ],
    );
  }
}
