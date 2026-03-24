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
  // UT MVP: 등교 전용 기본 항목
  const Map<String, List<String>> itemsMap = {
    '등교': ['보조배터리', '가방', '노트북'],
    '외출': ['지갑', '열쇠'],
  };

  return {
    '준비물': itemsMap[outingType] ?? ['지갑', '열쇠'],
    '행동': ['불 끄기'],
  };
}