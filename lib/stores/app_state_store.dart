import 'dart:convert';
import 'dart:io';

/// 应用状态持久化存储
class AppStateStore {
  static const String _stateFileName = 'app_state.json';

  File _resolveStateFile() {
    return File(
      '${Directory.current.path}${Platform.pathSeparator}$_stateFileName',
    );
  }

  Future<Map<String, dynamic>> readState() async {
    final File file = _resolveStateFile();
    if (!await file.exists()) return <String, dynamic>{};

    try {
      final String raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String, dynamic>{};
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> writeState(Map<String, dynamic> state) async {
    final File file = _resolveStateFile();
    final String raw = const JsonEncoder.withIndent('  ').convert(state);
    await file.writeAsString(raw, flush: true);
  }
}
