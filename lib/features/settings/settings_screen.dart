// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:fl_location/fl_location.dart';
import '../../data/prefs_service.dart';
import '../../data/place.dart';
import '../../services/geofence_service_wrapper.dart';
import '../../app/design_system.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _prepTime = '07:30';
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
  final _apiKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
  final pt = await PrefsService.getPrepTime();
  final pl = await PrefsService.getPlaces();
  final ap = await PrefsService.getActivePlaceId();

  final dndE = await PrefsService.isDndEnabled();
  final dndS = await PrefsService.getDndStart();
  final dndEnd = await PrefsService.getDndEnd();

  // ✅ 여기서 미리 다 받아두기
  final weatherE = await PrefsService.isWeatherEnabled();
  final dustE = await PrefsService.isDustEnabled();
  final tempS = await PrefsService.getTempSensitivity();
  final apiKey = await PrefsService.getWeatherApiKey();

  if (mounted) {
    setState(() {
      _prepTime = pt ?? '07:30';
      _places = pl;
      _activePlaceId = ap;
      _dndEnabled = dndE;
      _dndStart = dndS;
      _dndEnd = dndEnd;

      // ✅ setState 안에서는 이미 받아둔 값만 할당
      _weatherEnabled = weatherE;
      _dustEnabled = dustE;
      _tempSensitivity = tempS;
      _apiKeyCtrl.text = apiKey;

      _isLoading = false;
    });
  }
}

  Future<void> _pickTime() async {
    final parts = _prepTime.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
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

  Future<void> _saveApiKey() async {
    await PrefsService.setWeatherApiKey(_apiKeyCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API 키가 저장되었습니다.')));
    }
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
                    decoration: const InputDecoration(labelText: '상세 주소', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final loc = await FlLocation.getLocation();
                        setDialogState(() {
                          latCtrl.text = loc.latitude.toString();
                          lonCtrl.text = loc.longitude.toString();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('현재 위치의 좌표를 가져왔습니다.')));
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('위치를 가져오지 못했습니다: $e')));
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('설정', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const NeomeBottomNav(currentIndex: 1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('기본 설정'),
            Card(
              child: ListTile(
                title: const Text('준비 시작 시간'),
                subtitle: Text('매일 이 시간대에 외출 준비를 도와드려요: $_prepTime'),
                trailing: const Icon(Icons.access_time),
                onTap: _pickTime,
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('알림 방해금지'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('방해금지 모드'),
                    subtitle: const Text('설정한 시간대에는 알림을 보내지 않아요'),
                    value: _dndEnabled,
                    onChanged: _toggleDnd,
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
            _buildSectionHeader('자동 연동 설정 (OpenWeatherMap)'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('날씨 연동 (우산)'),
                    subtitle: const Text('비나 눈이 오면 체크리스트에 우산을 추가해요'),
                    value: _weatherEnabled,
                    onChanged: _toggleWeather,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('미세먼지 연동 (마스크)'),
                    subtitle: const Text('미세먼지 농도가 높으면 마스크를 추가해요'),
                    value: _dustEnabled,
                    onChanged: _toggleDust,
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
                            const Text('온도 민감도 설정', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(
                              _tempSensitivity > 0 ? '+${_tempSensitivity.toStringAsFixed(1)}°C' : '${_tempSensitivity.toStringAsFixed(1)}°C',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NeomeDesignSystem.primary),
                            ),
                          ],
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
                        const SizedBox(height: 12),
                        const Text('OpenWeatherMap API Key', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _apiKeyCtrl,
                                decoration: const InputDecoration(
                                  hintText: 'API 키를 입력하세요',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _saveApiKey,
                              child: const Text('저장'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '날씨 정보를 가져오기 위해 API 키가 필요합니다.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader('장소 관리'),
                IconButton(onPressed: _addPlace, icon: const Icon(Icons.add_circle, color: NeomeDesignSystem.primary)),
              ],
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
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isActive ? NeomeDesignSystem.primary.withOpacity(0.06) : Colors.white,
                    child: ListTile(
                      title: Text(p.name, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text('${p.lat}, ${p.lon}'),
                      leading: Radio<String>(
                        value: p.id,
                        groupValue: _activePlaceId,
                        onChanged: (id) => _setActivePlace(id!),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _deletePlace(p.id),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 40),
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
}
