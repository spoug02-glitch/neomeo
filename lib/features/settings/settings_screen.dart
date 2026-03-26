// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:fl_location/fl_location.dart';
import '../../data/prefs_service.dart';
import '../../data/place.dart';
import '../../services/geofence_service_wrapper.dart';
import '../../services/daily_notif_guard.dart';
import '../../services/notification_service.dart';
import '../../services/geofence_log.dart';
import '../../services/geocoding_service.dart';
import '../../app/design_system.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _prepTime;
  List<Place> _places = [];
  String? _activePlaceId;
  bool _isLoading = true;

  // DND settings
  bool _dndEnabled = false;
  String _dndStart = '12:00';
  String _dndEnd = '13:00';

  // Weather/Dust settings
  bool _weatherEnabled = false;
  bool _dustEnabled = false;
  double _tempSensitivity = 0.0;

  // 지오펜스 이벤트 로그
  List<String> _geoLogs = [];

  // 권한 상태
  PermissionStatus _notifStatus   = PermissionStatus.denied;
  PermissionStatus _locStatus     = PermissionStatus.denied;
  PermissionStatus _locBgStatus   = PermissionStatus.denied;
  PermissionStatus _batteryStatus = PermissionStatus.denied;
  bool _isPermissionsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPermissions();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadData() async {
    final pt = await PrefsService.getPrepTime();
    final pl = await PrefsService.getPlaces();
    final ap = await PrefsService.getActivePlaceId();

    final dndE = await PrefsService.isDndEnabled();
    final dndS = await PrefsService.getDndStart();
    final dndEnd = await PrefsService.getDndEnd();

    final weatherE = await PrefsService.isWeatherEnabled();
    final dustE = await PrefsService.isDustEnabled();
    final tempS = await PrefsService.getTempSensitivity();
    final logs = await GeofenceLog.getAll();

    if (mounted) {
      setState(() {
        _prepTime = pt;
        _places = pl;
        _activePlaceId = ap;
        _dndEnabled = dndE;
        _dndStart = dndS;
        _dndEnd = dndEnd;
        _weatherEnabled = weatherE;
        _dustEnabled = dustE;
        _tempSensitivity = tempS;
        _geoLogs = logs;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPermissions() async {
    final notif   = await Permission.notification.status;
    final loc     = await Permission.locationWhenInUse.status;
    final locBg   = await Permission.locationAlways.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    if (mounted) {
      setState(() {
        _notifStatus   = notif;
        _locStatus     = loc;
        _locBgStatus   = locBg;
        _batteryStatus = battery;
      });
    }
  }

  Future<String?> _reverseGeocode(double lat, double lon) =>
      GeocodingService.reverseGeocode(lat, lon);

  Future<void> _pickTime() async {
    TimeOfDay initial;
    if (_prepTime != null) {
      final parts = _prepTime!.split(':');
      initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } else {
      initial = TimeOfDay.now();
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      final s = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      await PrefsService.setPrepTime(s);
      setState(() => _prepTime = s);
    }
  }

  Future<void> _pickDndTime(bool isStart) async {
    final current = isStart ? _dndStart : _dndEnd;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (picked != null) {
      final s = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      if (isStart) {
        await PrefsService.setDndStart(s);
        setState(() => _dndStart = s);
      } else {
        await PrefsService.setDndEnd(s);
        setState(() => _dndEnd = s);
      }
    }
  }

  Future<void> _toggleDnd(bool val) async {
    await PrefsService.setDndEnabled(val);
    setState(() => _dndEnabled = val);
  }

  Future<void> _toggleWeather(bool val) async {
    await PrefsService.setWeatherEnabled(val);
    setState(() => _weatherEnabled = val);
  }

  Future<void> _toggleDust(bool val) async {
    await PrefsService.setDustEnabled(val);
    setState(() => _dustEnabled = val);
  }

  Future<void> _updateSensitivity(double val) async {
    await PrefsService.setTempSensitivity(val);
    setState(() => _tempSensitivity = val);
  }

  Future<void> _addPlace() async {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final detailedAddressCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lonCtrl = TextEditingController();
    final nameFocusNode = FocusNode();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          nameFocusNode.addListener(() {
            setDialogState(() {});
          });
          return AlertDialog(
            title: const Text('장소 추가'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    focusNode: nameFocusNode,
                    style: TextStyle(
                      color: nameFocusNode.hasFocus ? Colors.black : Colors.grey.shade400,
                    ),
                    decoration: InputDecoration(
                      labelText: '장소 이름',
                      labelStyle: TextStyle(
                        color: nameFocusNode.hasFocus ? Colors.black : Colors.grey.shade400,
                      ),
                      hintText: '예: 우리집, 회사',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(labelText: '주소', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailedAddressCtrl,
                    decoration: const InputDecoration(labelText: '상세 주소 (선택)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        // GPS 서비스 활성화 확인
                        final svcEnabled = await FlLocation.isLocationServicesEnabled;
                        if (!svcEnabled) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('위치 서비스(GPS)가 꺼져 있어요. 설정에서 켜주세요.')));
                          }
                          return;
                        }
                        var locPerm = await FlLocation.checkLocationPermission();
                        if (locPerm == LocationPermission.denied ||
                            locPerm == LocationPermission.deniedForever) {
                          locPerm = await FlLocation.requestLocationPermission();
                          if (locPerm == LocationPermission.denied ||
                              locPerm == LocationPermission.deniedForever) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('위치 권한이 필요해요. 설정에서 허용해주세요.')));
                            }
                            return;
                          }
                        }
                        final loc = await FlLocation.getLocation(
                          accuracy: LocationAccuracy.high,
                          timeLimit: const Duration(seconds: 15),
                        );
                        setDialogState(() {
                          latCtrl.text = loc.latitude.toStringAsFixed(6);
                          lonCtrl.text = loc.longitude.toStringAsFixed(6);
                        });
                        // 주소 역지오코딩
                        final addr = await _reverseGeocode(loc.latitude, loc.longitude);
                        if (addr != null && addressCtrl.text.trim().isEmpty) {
                          setDialogState(() => addressCtrl.text = addr);
                        }
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(addr != null ? '위치: $addr' : '좌표를 가져왔습니다.'),
                          ));
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('위치를 가져오지 못했습니다: $e')));
                        }
                      }
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('현재 위치 가져오기'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('추가')),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final name = nameCtrl.text.trim();
      final address = addressCtrl.text.trim();
      final detailedAddress = detailedAddressCtrl.text.trim();
      final lat = double.tryParse(latCtrl.text.trim()) ?? 0.0;
      final lon = double.tryParse(lonCtrl.text.trim()) ?? 0.0;

      if (name.isNotEmpty) {
        final newPlace = Place(
          id: const Uuid().v4(),
          name: name,
          address: address.isNotEmpty ? address : null,
          detailedAddress: detailedAddress.isNotEmpty ? detailedAddress : null,
          lat: lat,
          lon: lon,
        );
        final newList = [..._places, newPlace];
        await PrefsService.savePlaces(newList);
        if (_activePlaceId == null || _activePlaceId!.isEmpty) {
          await _setActivePlace(newPlace.id);
        }
        _loadData();
      }
    }
  }

  Future<void> _editPlace(Place place) async {
    final nameCtrl           = TextEditingController(text: place.name);
    final addressCtrl        = TextEditingController(text: place.address ?? '');
    final detailedAddressCtrl = TextEditingController(text: place.detailedAddress ?? '');
    final latCtrl            = TextEditingController(text: place.lat != 0.0 ? place.lat.toString() : '');
    final lonCtrl            = TextEditingController(text: place.lon != 0.0 ? place.lon.toString() : '');
    bool isFetching = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('위치 수정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '장소 이름', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(labelText: '주소', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailedAddressCtrl,
                    decoration: const InputDecoration(labelText: '상세 주소 (선택)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isFetching ? null : () async {
                      setDialogState(() => isFetching = true);
                      try {
                        // GPS 서비스 활성화 확인
                        final svcEnabled = await FlLocation.isLocationServicesEnabled;
                        if (!svcEnabled) {
                          setDialogState(() => isFetching = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('위치 서비스(GPS)가 꺼져 있어요. 설정에서 켜주세요.')));
                          }
                          return;
                        }
                        var locPerm = await FlLocation.checkLocationPermission();
                        if (locPerm == LocationPermission.denied ||
                            locPerm == LocationPermission.deniedForever) {
                          locPerm = await FlLocation.requestLocationPermission();
                          if (locPerm == LocationPermission.denied ||
                              locPerm == LocationPermission.deniedForever) {
                            setDialogState(() => isFetching = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('위치 권한이 필요해요. 설정에서 허용해주세요.')));
                            }
                            return;
                          }
                        }
                        final loc = await FlLocation.getLocation(
                          accuracy: LocationAccuracy.high,
                          timeLimit: const Duration(seconds: 15),
                        );
                        setDialogState(() {
                          latCtrl.text = loc.latitude.toStringAsFixed(6);
                          lonCtrl.text  = loc.longitude.toStringAsFixed(6);
                        });
                        // 주소 역지오코딩
                        final addr = await _reverseGeocode(loc.latitude, loc.longitude);
                        setDialogState(() {
                          if (addr != null && addressCtrl.text.trim().isEmpty) {
                            addressCtrl.text = addr;
                          }
                          isFetching = false;
                        });
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(addr != null ? '위치: $addr' : '좌표를 가져왔어요.'),
                          ));
                        }
                      } catch (_) {
                        setDialogState(() => isFetching = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('위치를 가져오지 못했어요.')));
                        }
                      }
                    },
                    icon: isFetching
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(isFetching ? '가져오는 중...' : '현재 위치 가져오기'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final updated = Place(
        id: place.id,
        name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : place.name,
        address: addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null,
        detailedAddress: detailedAddressCtrl.text.trim().isNotEmpty ? detailedAddressCtrl.text.trim() : null,
        lat: double.tryParse(latCtrl.text.trim()) ?? place.lat,
        lon: double.tryParse(lonCtrl.text.trim()) ?? place.lon,
      );
      final newList = _places.map((p) => p.id == place.id ? updated : p).toList();
      await PrefsService.savePlaces(newList);
      if (_activePlaceId == place.id) {
        await GeofenceServiceWrapper().startMonitoringActivePlace();
      }
      _loadData();
    }
  }

  Future<void> _setActivePlace(String id) async {
    await PrefsService.setActivePlaceId(id);
    await GeofenceServiceWrapper().startMonitoringActivePlace();
    setState(() => _activePlaceId = id);
  }

  Future<void> _deletePlace(String id) async {
    final newList = _places.where((p) => p.id != id).toList();
    await PrefsService.savePlaces(newList);
    if (_activePlaceId == id) {
      if (newList.isNotEmpty) {
        await _setActivePlace(newList.first.id);
      } else {
        await PrefsService.setActivePlaceId('');
        await GeofenceServiceWrapper().stopMonitoring();
        setState(() => _activePlaceId = null);
      }
    }
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('설정', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const NeomeBottomNav(currentIndex: 3),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 권한 섹션은 접어둔 상태로 시작 — 설정 진입 시 핵심 내용에 먼저 집중하도록
            _buildSectionHeader('권한 관리'),
            Card(
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _isPermissionsExpanded = !_isPermissionsExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.security_outlined, size: 20, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('필요한 권한',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                          AnimatedRotation(
                            turns: _isPermissionsExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.expand_more, size: 20, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isPermissionsExpanded) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await openAppSettings();
                            await Future.delayed(const Duration(milliseconds: 800));
                            _loadPermissions();
                          },
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('앱 설정 열기'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NeomeDesignSystem.primary,
                            side: BorderSide(color: NeomeDesignSystem.primary.withOpacity(0.4)),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    _buildPermissionTile(
                      icon: Icons.notifications_outlined,
                      title: '알림',
                      subtitle: '외출 감지 시 체크리스트 알림',
                      status: _notifStatus,
                    ),
                    const Divider(height: 1),
                    _buildPermissionTile(
                      icon: Icons.location_on_outlined,
                      title: '위치 (앱 사용 중)',
                      subtitle: '외출 감지에 필요해요',
                      status: _locStatus,
                    ),
                    const Divider(height: 1),
                    _buildPermissionTile(
                      icon: Icons.location_searching,
                      title: '위치 (항상 허용)',
                      subtitle: '앱이 꺼진 상태에서도 감지해요',
                      status: _locBgStatus,
                    ),
                    const Divider(height: 1),
                    _buildPermissionTile(
                      icon: Icons.battery_saver_outlined,
                      title: '배터리 최적화 제외',
                      subtitle: '백그라운드 동작이 안정적으로 유지돼요',
                      status: _batteryStatus,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ── 추천 기준 설정 ──────────────────────────────────
            // 사용자의 체질과 환경에 맞춰 준비물 추천을 개인화하는 섹션
            _buildSectionHeader('추천 기준 설정'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('날씨 연동'),
                    // 기능의 결과를 구체적으로 설명해 설정의 의미를 명확히
                    subtitle: const Text('비가 올 것 같은 날, 체크리스트에 자동으로 우산을 추가해요'),
                    value: _weatherEnabled,
                    onChanged: _toggleWeather,
                    activeColor: NeomeDesignSystem.primary,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('미세먼지 연동'),
                    // 설정이 미치는 영향을 사용자 관점에서 서술
                    subtitle: const Text('미세먼지가 나쁜 날, 마스크를 빠뜨리지 않도록 알려줘요'),
                    value: _dustEnabled,
                    onChanged: _toggleDust,
                    activeColor: NeomeDesignSystem.primary,
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('온도 민감도', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(
                              _tempSensitivity > 0 ? '+${_tempSensitivity.toStringAsFixed(1)}°C' : '${_tempSensitivity.toStringAsFixed(1)}°C',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NeomeDesignSystem.primary),
                            ),
                          ],
                        ),
                        // 설정의 영향을 한 줄로 명확히 설명
                        const SizedBox(height: 4),
                        const Text(
                          '내 체질에 맞게 추천 옷차림을 조절해요',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: _tempSensitivity,
                          min: -5.0,
                          max: 5.0,
                          divisions: 10,
                          label: _tempSensitivity.toStringAsFixed(1),
                          onChanged: _updateSensitivity,
                          activeColor: NeomeDesignSystem.primary,
                        ),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('추위를 많이 탐', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('보통', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('더위를 많이 탐', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ── 알림 및 환경 설정 ────────────────────────────────
            // 알림 시점·방해금지 등 앱의 행동 방식을 제어하는 섹션
            _buildSectionHeader('알림 및 환경 설정'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('방해금지 모드'),
                    // 어떤 상황에 유용한지를 구체적으로 서술
                    subtitle: const Text('취침 중이나 집중이 필요한 시간대엔 알림을 보내지 않아요'),
                    value: _dndEnabled,
                    onChanged: _toggleDnd,
                    activeColor: NeomeDesignSystem.primary,
                  ),
                  if (_dndEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('시작 시간'),
                      trailing: Text(_dndStart, style: const TextStyle(fontWeight: FontWeight.bold, color: NeomeDesignSystem.primary)),
                      onTap: () => _pickDndTime(true),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('종료 시간'),
                      trailing: Text(_dndEnd, style: const TextStyle(fontWeight: FontWeight.bold, color: NeomeDesignSystem.primary)),
                      onTap: () => _pickDndTime(false),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      '장소 관리',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: NeomeDesignSystem.textSub),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('장소 추가는 현재 준비 중이에요. 추후 지원될 예정이에요.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Icon(Icons.add_circle, color: NeomeDesignSystem.textHint, size: 24),
                  ),
                ],
              ),
            ),
            if (_places.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('등록된 장소가 없습니다.')))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _places.length,
                itemBuilder: (ctx, i) {
                  final p = _places[i];
                  final isActive = p.id == _activePlaceId;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 장소 정보 행 ──────────────────────────────
                        ListTile(
                          onTap: () => _editPlace(p),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          title: Text(
                            p.name,
                            style: TextStyle(
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              color: isActive ? NeomeDesignSystem.primary : const Color(0xFF1E293B),
                            ),
                          ),
                          subtitle: p.address != null
                              ? Text(p.address!, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
                              : null,
                          leading: Radio<String>(
                            value: p.id,
                            groupValue: _activePlaceId,
                            onChanged: (id) => _setActivePlace(id!),
                            activeColor: NeomeDesignSystem.primary,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () => _deletePlace(p.id),
                          ),
                        ),
                        // ── 체크리스트 2개 링크 (나갈때 / 들어올때) ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: _checklistButton(
                                  context,
                                  icon: '🚪',
                                  label: '집 나갈 때',
                                  onTap: () => context.push(
                                    '/checklist-settings?placeId=${p.id}&type=${Uri.encodeComponent('나갈때')}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _checklistButton(
                                  context,
                                  icon: '🏠',
                                  label: '집 들어올 때',
                                  onTap: () => context.push(
                                    '/checklist-settings?placeId=${p.id}&type=${Uri.encodeComponent('들어올때')}',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader('지오펜스 이벤트 로그'),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      color: NeomeDesignSystem.textSub,
                      tooltip: '새로고침',
                      onPressed: () async {
                        final logs = await GeofenceLog.getAll();
                        if (mounted) setState(() => _geoLogs = logs);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: NeomeDesignSystem.textSub,
                      tooltip: '로그 초기화',
                      onPressed: () async {
                        await GeofenceLog.clear();
                        if (mounted) setState(() => _geoLogs = []);
                      },
                    ),
                  ],
                ),
              ],
            ),
            Card(
              child: _geoLogs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '기록된 이벤트가 없어요.\n집을 나갔다 돌아온 후 새로고침 해보세요.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _geoLogs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 12, endIndent: 12),
                      itemBuilder: (_, i) {
                        final entry = _geoLogs[i];
                        // PENDING/NOTIFIED는 강조
                        final isKey = entry.contains('PENDING') ||
                            entry.contains('NOTIFIED') ||
                            entry.contains('atHome');
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Text(
                            entry,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: isKey
                                  ? NeomeDesignSystem.primary
                                  : const Color(0xFF475569),
                              fontWeight: isKey
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 40),
            OutlinedButton.icon(
              onPressed: () async {
                final p = await SharedPreferences.getInstance();
                await p.remove('onboarding_done');
                if (mounted) context.go('/onboarding');
              },
              icon: const Icon(Icons.replay, size: 16),
              label: const Text('온보딩 다시 보기'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: NeomeDesignSystem.textSub,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await GeofenceServiceWrapper().startMonitoringActivePlace();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('지오펜스 서비스를 재시작했어요')),
                  );
                  final logs = await GeofenceLog.getAll();
                  setState(() => _geoLogs = logs);
                }
              },
              icon: const Icon(Icons.location_on_outlined, size: 16),
              label: const Text('지오펜스 재시작'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: NeomeDesignSystem.textSub,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await DailyNotifGuard.resetCooldown();
                await NotificationService().showDeparturePrompt();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('테스트 알림을 보냈어요!')),
                  );
                }
              },
              icon: const Icon(Icons.notifications_active, size: 16),
              label: const Text('알림 테스트 (쿨다운 무시)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: NeomeDesignSystem.textSub,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    )); // PopScope
  }

  /// 장소 카드 내 체크리스트 링크 버튼 (나갈때/들어올때)
  Widget _checklistButton(
    BuildContext context, {
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: NeomeDesignSystem.textSub),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required PermissionStatus status,
  }) {
    final granted = status.isGranted;
    return ListTile(
      leading: Icon(icon, color: granted ? NeomeDesignSystem.primary : const Color(0xFFCBD5E1), size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: granted
              ? const Color(0xFF22C55E).withOpacity(0.1)
              : const Color(0xFFEF4444).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          granted ? '허용됨' : '차단됨',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: granted ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          ),
        ),
      ),
    );
  }
}
