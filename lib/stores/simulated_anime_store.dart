import 'dart:convert';
import 'dart:io';

import '../models/simulated_anime.dart';

/// Persists debug SimulatedAnime entries to app_state.json.
class SimulatedAnimeStore {
  static const String _storageKey = 'debug_simulated_animes';

  File get _file => File('${Directory.current.path}${Platform.pathSeparator}app_state.json');

  Future<List<SimulatedAnime>> load() async {
    if (!await _file.exists()) return <SimulatedAnime>[];
    try {
      final String raw = await _file.readAsString();
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <SimulatedAnime>[];
      final dynamic listRaw = decoded[_storageKey];
      if (listRaw is! List) return <SimulatedAnime>[];
      return listRaw
          .whereType<Map<String, dynamic>>()
          .map(SimulatedAnime.fromJson)
          .toList();
    } catch (_) {
      return <SimulatedAnime>[];
    }
  }

  Future<void> save(List<SimulatedAnime> animes) async {
    try {
      // Read existing state, update key, write back.
      final Map<String, dynamic> state;
      if (await _file.exists()) {
        final String raw = await _file.readAsString();
        final dynamic d = jsonDecode(raw);
        state = d is Map<String, dynamic> ? d : <String, dynamic>{};
      } else {
        state = <String, dynamic>{};
      }
      state[_storageKey] = animes.map((a) => a.toJson()).toList();
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(state),
        flush: true,
      );
    } catch (_) {
      // Non-fatal debug feature.
    }
  }
}
