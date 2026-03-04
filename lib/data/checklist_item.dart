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
    '출근': ['지갑', '교통카드', '열쇠', '폰', '신분증'],
    '운동': ['운동복', '물병', '수건', '운동화', '이어폰'],
    '약속': ['지갑', '폰', '열쇠', '보조배터리'],
    '회의': ['노트북', '충전기', '명함', '노트/펜', '테블릿'],
  };

  return {
    '준비물': itemsMap[outingType] ?? [],
    '행동': ['가스불', '형광등'],
  };
}