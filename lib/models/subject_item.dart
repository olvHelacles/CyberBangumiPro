import '../constants.dart';

/// 条目基础信息
class SubjectItem {
  const SubjectItem({
    required this.subjectId,
    required this.subjectUrl,
    required this.nameCn,
    required this.nameOrigin,
    required this.coverUrl,
    this.updateTime = '',
    this.localCoverPath = '',
  });

  final String subjectId;
  final String subjectUrl;
  final String nameCn;
  final String nameOrigin;
  final String coverUrl;
  final String updateTime;
  final String localCoverPath;

  String get displayName => nameCn.isNotEmpty ? nameCn : nameOrigin;

  factory SubjectItem.fromJson(Map<String, dynamic> json) {
    return SubjectItem(
      subjectId: readJsonString(json['subject_id']),
      subjectUrl: readJsonString(json['subject_url']),
      nameCn: readJsonString(json['name_cn']),
      nameOrigin: readJsonString(json['name_origin']),
      coverUrl: readJsonString(json['cover_url']),
      updateTime: readJsonString(json['update_time']),
    );
  }

  SubjectItem copyWith({
    String? subjectId,
    String? subjectUrl,
    String? nameCn,
    String? nameOrigin,
    String? coverUrl,
    String? updateTime,
    String? localCoverPath,
  }) {
    return SubjectItem(
      subjectId: subjectId ?? this.subjectId,
      subjectUrl: subjectUrl ?? this.subjectUrl,
      nameCn: nameCn ?? this.nameCn,
      nameOrigin: nameOrigin ?? this.nameOrigin,
      coverUrl: coverUrl ?? this.coverUrl,
      updateTime: updateTime ?? this.updateTime,
      localCoverPath: localCoverPath ?? this.localCoverPath,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'subject_id': subjectId,
      'subject_url': subjectUrl,
      'name_cn': nameCn,
      'name_origin': nameOrigin,
      'cover_url': coverUrl,
      'update_time': updateTime,
    };
  }
}

/// 单日更新列表
class DaySchedule {
  const DaySchedule({required this.weekday, required this.items});

  final String weekday;
  final List<SubjectItem> items;

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawItems =
        (json['items'] as List<dynamic>?) ?? <dynamic>[];
    return DaySchedule(
      weekday: (json['weekday'] ?? '').toString(),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(SubjectItem.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'weekday': weekday,
      'items': items.map((SubjectItem item) => item.toJson()).toList(),
    };
  }
}
