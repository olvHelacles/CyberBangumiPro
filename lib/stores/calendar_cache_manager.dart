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
    if (decoded is! List<dynamic>) return <DaySchedule>[];

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DaySchedule.fromJson)
        .toList();
  }

  Future<void> save(List<DaySchedule> schedule) async {
    final File file = await _ensureCacheFile();
    final String raw = const JsonEncoder.withIndent('  ').convert(
      schedule.map((DaySchedule day) => day.toJson()).toList(),
    );
    await file.writeAsString(raw, flush: true);
  }
}
