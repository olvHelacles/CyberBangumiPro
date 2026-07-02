import 'dart:convert';
import 'dart:io';

import '../models/watch_archive_entry.dart';

/// 关注归档持久化存储
class WatchArchiveStore {
  static const String _archiveFileName = 'watch_archive.json';

  File _resolveArchiveFile() {
    return File(
      '${Directory.current.path}${Platform.pathSeparator}$_archiveFileName',
    );
  }

  Future<List<WatchArchiveEntry>> load() async {
    final File file = _resolveArchiveFile();
    if (!await file.exists()) {
      await file.writeAsString('[]', flush: true);
      return <WatchArchiveEntry>[];
    }

    try {
      final String raw = await file.readAsString();
      if (raw.trim().isEmpty) return <WatchArchiveEntry>[];
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return <WatchArchiveEntry>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(WatchArchiveEntry.fromJson)
          .toList();
    } catch (_) {
      return <WatchArchiveEntry>[];
    }
  }

  Future<void> save(List<WatchArchiveEntry> entries) async {
    final File file = _resolveArchiveFile();
    final String raw = const JsonEncoder.withIndent('  ').convert(
      entries.map((WatchArchiveEntry e) => e.toJson()).toList(),
    );
    await file.writeAsString(raw, flush: true);
  }

  Future<void> appendEntries(List<WatchArchiveEntry> entries) async {
    if (entries.isEmpty) return;
    final List<WatchArchiveEntry> current = await load();
    current.addAll(entries);
    await save(current);
  }
}
