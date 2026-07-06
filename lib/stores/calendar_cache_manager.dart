import 'dart:convert';
import 'dart:io';

import '../models/subject_item.dart';

/// 日历缓存管理器
class CalendarCacheManager {
  static const String _cacheFileName = 'calendar_cache.json';

  File? _cacheFile;

  Directory _resolveCalendarCacheDir() {
    return Directory.current;
  }

  Future<File> _ensureCacheFile() async {
    if (_cacheFile != null) return _cacheFile!;
    final Directory targetDir = _resolveCalendarCacheDir();
    _cacheFile = File(
      '${targetDir.path}${Platform.pathSeparator}$_cacheFileName',
    );
    return _cacheFile!;
  }

  Future<List<DaySchedule>> load() async {
    final File file = await _ensureCacheFile();
    if (!await file.exists()) return <DaySchedule>[];

    final String raw = await file.readAsString();
    if (raw.trim().isEmpty) return <DaySchedule>[];

    final dynamic decoded = jsonDecode(raw);
    // New format: {"schedule": [...], "startDates": {...}}
    if (decoded is Map<String, dynamic>) {
      final dynamic scheduleRaw = decoded['schedule'];
      if (scheduleRaw is List<dynamic>) {
        return scheduleRaw
            .whereType<Map<String, dynamic>>()
            .map(DaySchedule.fromJson)
            .toList();
      }
      return <DaySchedule>[];
    }
    // Legacy format: flat list
    if (decoded is List<dynamic>) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DaySchedule.fromJson)
          .toList();
    }
    return <DaySchedule>[];
  }

  Future<void> save(List<DaySchedule> schedule) async {
    final File file = await _ensureCacheFile();
    final String raw = const JsonEncoder.withIndent('  ').convert(
      schedule.map((DaySchedule day) => day.toJson()).toList(),
    );
    await file.writeAsString(raw, flush: true);
  }

  /// Save both schedule and subject start dates.
  /// startDates key → ISO 8601 string.
  Future<void> saveWithStartDates(
    List<DaySchedule> schedule,
    Map<String, DateTime> startDates,
  ) async {
    final File file = await _ensureCacheFile();
    final Map<String, dynamic> data = <String, dynamic>{
      'schedule': schedule.map((DaySchedule day) => day.toJson()).toList(),
    };
    if (startDates.isNotEmpty) {
      data['startDates'] = startDates.map(
        (String k, DateTime v) => MapEntry<String, dynamic>(k, v.toIso8601String()),
      );
    }
    final String raw = const JsonEncoder.withIndent('  ').convert(data);
    await file.writeAsString(raw, flush: true);
  }

  /// Load start dates from the new-format cache. Returns empty map if not
  /// present (legacy cache or missing data).
  Future<Map<String, DateTime>> loadStartDates() async {
    final File file = await _ensureCacheFile();
    if (!await file.exists()) return <String, DateTime>{};

    final String raw = await file.readAsString();
    if (raw.trim().isEmpty) return <String, DateTime>{};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, DateTime>{};
      final dynamic datesRaw = decoded['startDates'];
      if (datesRaw is! Map) return <String, DateTime>{};
      final Map<String, DateTime> result = <String, DateTime>{};
      datesRaw.forEach((dynamic k, dynamic v) {
        if (k is String && v is String) {
          final DateTime? dt = DateTime.tryParse(v);
          if (dt != null) result[k] = dt;
        }
      });
      return result;
    } catch (_) {
      return <String, DateTime>{};
    }
  }
}
