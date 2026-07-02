import 'subject_item.dart';

/// 关注归档条目
class WatchArchiveEntry {
  const WatchArchiveEntry({
    required this.subjectId,
    required this.nameCn,
    required this.nameJp,
    required this.quarter,
    required this.text,
    required this.archivedAt,
  });

  final String subjectId;
  final String nameCn;
  final String nameJp;
  final String quarter;
  final String text;
  final String archivedAt;

  factory WatchArchiveEntry.fromSubject(
    SubjectItem item, {
    required String quarter,
  }) {
    final String cn = item.nameCn.trim();
    final String jpRaw = item.nameOrigin.trim();
    final String jp = jpRaw.isNotEmpty
        ? jpRaw
        : (item.displayName.isNotEmpty ? item.displayName : item.subjectId);
    final String text = cn.isNotEmpty
        ? '$cn / $jp（$quarter）'
        : '$jp（$quarter）';

    return WatchArchiveEntry(
      subjectId: item.subjectId,
      nameCn: cn,
      nameJp: jp,
      quarter: quarter,
      text: text,
      archivedAt: DateTime.now().toIso8601String(),
    );
  }

  factory WatchArchiveEntry.fromJson(Map<String, dynamic> json) {
    return WatchArchiveEntry(
      subjectId: (json['subject_id'] ?? '').toString(),
      nameCn: (json['name_cn'] ?? '').toString(),
      nameJp: (json['name_jp'] ?? '').toString(),
      quarter: (json['quarter'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      archivedAt: (json['archived_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'subject_id': subjectId,
      'name_cn': nameCn,
      'name_jp': nameJp,
      'quarter': quarter,
      'text': text,
      'archived_at': archivedAt,
    };
  }
}
