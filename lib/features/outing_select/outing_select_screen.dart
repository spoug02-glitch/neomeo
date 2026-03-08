// lib/features/outing_select/outing_select_screen.dart
//
// 지오펜스 이탈 알림 탭 시 진입하는 화면.
// 외출 유형(등교/출근/학원/기타)을 선택하면 해당 체크리스트로 자동 이동한다.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/design_system.dart';

const _outingTypes = [
  ('등교', '🎒'),
  ('출근', '🏢'),
  ('학원', '📚'),
  ('기타', '✏️'),
];

class OutingSelectScreen extends StatelessWidget {
  const OutingSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeomeDesignSystem.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WindowLogo(size: 36),
              const SizedBox(height: 24),
              const Text(
                '어디 가세요?',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '외출 유형을 선택하면 체크리스트를 바로 열어드려요',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 36),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.2,
                  children: _outingTypes.map((t) {
                    return _TypeTile(
                      emoji: t.$2,
                      label: t.$1,
                      onTap: () => _onSelect(context, t.$1),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSelect(BuildContext context, String type) {
    if (type == '기타') {
      _showCustomDialog(context);
    } else {
      context.go('/checklist?type=${Uri.encodeComponent(type)}');
    }
  }

  Future<void> _showCustomDialog(BuildContext context) async {
    String custom = '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('어디 가시나요?'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 병원, 쇼핑'),
          onChanged: (v) => custom = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, custom),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty && context.mounted) {
      context.go('/checklist?type=${Uri.encodeComponent(result.trim())}');
    }
  }
}

class _TypeTile extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  const _TypeTile({required this.emoji, required this.label, required this.onTap});

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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const Spacer(),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
