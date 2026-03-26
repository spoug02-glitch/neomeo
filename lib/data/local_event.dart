// lib/data/local_event.dart
import 'package:uuid/uuid.dart';

/// 일정 중요도: none=회색, medium=초록, high=주황
enum EventImportance { none, medium, high }

/// 반복 유형
enum RepeatType {
  none,        // 일회성
  daily,       // 1일마다
  weeklyDays,  // 매주 특정 요일
  weekly,      // 일주일마다 (동일 요일)
  monthly,     // 매달 동일 날짜
}

class LocalEventItem {
  final String id;
  final String label;
  bool checked;
  final DateTime? deadline; // 행동 아이템 완료 기한

  LocalEventItem({
    String? id,
    required this.label,
    this.checked = false,
    this.deadline,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'checked': checked,
        if (deadline != null) 'deadline': deadline!.toIso8601String(),
      };

  factory LocalEventItem.fromJson(Map<String, dynamic> json) => LocalEventItem(
        id: json['id'] as String? ?? const Uuid().v4(),
        label: json['label'] as String? ?? '',
        checked: json['checked'] as bool? ?? false,
        deadline: json['deadline'] != null
            ? DateTime.tryParse(json['deadline'] as String)
            : null,
      );

  LocalEventItem copyWith({bool? checked, DateTime? deadline}) => LocalEventItem(
        id: id,
        label: label,
        checked: checked ?? this.checked,
        deadline: deadline ?? this.deadline,
      );
}

class LocalEvent {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime? endTime;
  final EventImportance importance;
  final RepeatType repeatType;
  final List<int> repeatDays;           // 0=일,1=월,...,6=토
  final bool repeatExcludeWeekends;     // 영업일만 (주말 제외)
  final bool isChecklistMode;           // 체크리스트 vs 메모
  final List<LocalEventItem> checklistItems;
  final String? linkedChecklistType;   // '나갈때' → GPS 자동 연동
  final String? placeId;               // GPS 연동 장소
  final String? parentEventId;         // 후속 일정의 부모
  bool isCompleted;
  int usageCount;
  final DateTime createdAt;

  LocalEvent({
    String? id,
    required this.title,
    required this.startTime,
    this.endTime,
    this.importance = EventImportance.none,
    this.repeatType = RepeatType.none,
    this.repeatDays = const [],
    this.repeatExcludeWeekends = false,
    this.isChecklistMode = false,
    this.checklistItems = const [],
    this.linkedChecklistType,
    this.placeId,
    this.parentEventId,
    this.isCompleted = false,
    this.usageCount = 0,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startTime': startTime.toIso8601String(),
        if (endTime != null) 'endTime': endTime!.toIso8601String(),
        'importance': importance.index,
        'repeatType': repeatType.index,
        'repeatDays': repeatDays,
        'repeatExcludeWeekends': repeatExcludeWeekends,
        'isChecklistMode': isChecklistMode,
        'checklistItems': checklistItems.map((e) => e.toJson()).toList(),
        if (linkedChecklistType != null)
          'linkedChecklistType': linkedChecklistType,
        if (placeId != null) 'placeId': placeId,
        if (parentEventId != null) 'parentEventId': parentEventId,
        'isCompleted': isCompleted,
        'usageCount': usageCount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LocalEvent.fromJson(Map<String, dynamic> json) => LocalEvent(
        id: json['id'] as String? ?? const Uuid().v4(),
        title: json['title'] as String? ?? '제목 없음',
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.tryParse(json['endTime'] as String)
            : null,
        importance:
            EventImportance.values[json['importance'] as int? ?? 0],
        repeatType:
            RepeatType.values[json['repeatType'] as int? ?? 0],
        repeatDays:
            (json['repeatDays'] as List<dynamic>?)?.cast<int>() ?? [],
        repeatExcludeWeekends:
            json['repeatExcludeWeekends'] as bool? ?? false,
        isChecklistMode: json['isChecklistMode'] as bool? ?? false,
        checklistItems: (json['checklistItems'] as List<dynamic>?)
                ?.map((e) =>
                    LocalEventItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        linkedChecklistType: json['linkedChecklistType'] as String?,
        placeId: json['placeId'] as String?,
        parentEventId: json['parentEventId'] as String?,
        isCompleted: json['isCompleted'] as bool? ?? false,
        usageCount: json['usageCount'] as int? ?? 0,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  LocalEvent copyWith({
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    EventImportance? importance,
    RepeatType? repeatType,
    List<int>? repeatDays,
    bool? repeatExcludeWeekends,
    bool? isChecklistMode,
    List<LocalEventItem>? checklistItems,
    bool? isCompleted,
    int? usageCount,
  }) =>
      LocalEvent(
        id: id,
        title: title ?? this.title,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        importance: importance ?? this.importance,
        repeatType: repeatType ?? this.repeatType,
        repeatDays: repeatDays ?? this.repeatDays,
        repeatExcludeWeekends:
            repeatExcludeWeekends ?? this.repeatExcludeWeekends,
        isChecklistMode: isChecklistMode ?? this.isChecklistMode,
        checklistItems: checklistItems ?? this.checklistItems,
        linkedChecklistType: linkedChecklistType,
        placeId: placeId,
        parentEventId: parentEventId,
        isCompleted: isCompleted ?? this.isCompleted,
        usageCount: usageCount ?? this.usageCount,
        createdAt: createdAt,
      );
}
