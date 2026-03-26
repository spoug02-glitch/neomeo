// lib/data/checklist_item.dart
// In-memory checklist item model (not persisted — resets each outing session).

class ChecklistItem {
  final String id;
  final String label;
  final String category; // '준비물' or '행동'
  bool checked;

  ChecklistItem({
    required this.id,
    required this.label,
    required this.category,
    this.checked = false,
  });
}

// Default items per outing type, split by category
Map<String, List<String>> defaultItemsFor(String outingType) {
  const Map<String, List<String>> itemsMap = {
    '등교':    ['보조배터리', '가방', '노트북'],
    '외출':    ['지갑', '열쇠'],
    '나갈때':  ['지갑', '열쇠', '휴대폰'],
    '들어올때': ['손 씻기'],
  };

  const Map<String, List<String>> actionsMap = {
    '들어올때': ['짐 정리하기'],
  };

  return {
    '준비물': itemsMap[outingType] ?? ['지갑', '열쇠'],
    '행동': actionsMap[outingType] ?? ['불 끄기'],
  };
}