import 'dart:math' as math;

import 'subject_progress.dart';

/// A debug-only simulated anime for testing watchlist sort, periodic check,
/// and other time-dependent behaviors without relying on the real Bangumi API.
class SimulatedAnime {
  const SimulatedAnime({
    required this.subjectId,
    required this.title,
    required this.weekdayJst,
    required this.broadcastTimeJst,
    required this.firstEpisodeAirdate,
    required this.totalEpisodes,
    this.apiUpdateDelayMinutes = 5,
    this.episodeIntervalDays = 7,
  });

  final String subjectId;
  final String title;
  final String weekdayJst;
  final String broadcastTimeJst;
  final DateTime firstEpisodeAirdate;
  final int totalEpisodes;
  final int apiUpdateDelayMinutes;
  final int episodeIntervalDays;

  /// How many episodes the simulated API would report as aired by [now],
  /// taking into account the broadcast schedule and API update delay.
  int availableEpisodesAt(DateTime now) {
    if (totalEpisodes <= 0) return 0;
    final RegExpMatch? tm = RegExp(r'^(\d{1,2}):(\d{2})$')
        .firstMatch(broadcastTimeJst);
    if (tm == null) return 0;
    final int hour = int.parse(tm.group(1)!);
    final int minute = int.parse(tm.group(2)!);

    int count = 0;
    DateTime cursor = firstEpisodeAirdate;
    while (count < totalEpisodes) {
      // The moment the API "reveals" this episode to clients.
      // broadcastTimeJst is in the user's local timezone.
      final DateTime apiReveal = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        hour,
        minute,
      ).add(Duration(minutes: apiUpdateDelayMinutes));
      if (now.isBefore(apiReveal)) break;
      count++;
      cursor = cursor.add(Duration(days: episodeIntervalDays));
    }
    return count;
  }

  /// Generate a SubjectProgress that matches what the "simulated API"
  /// would return right now.
  SubjectProgress generateProgress(DateTime now) {
    final int ep = availableEpisodesAt(now);
    return SubjectProgress(
      totalEpsDeclared: totalEpisodes,
      airedEps: ep,
      latestAiredEp: ep > 0 ? ep : null,
      latestAiredAt: now.toUtc(),
      progressText: '$ep/$totalEpisodes',
      latestAiredAtLabel: ep > 0 ? broadcastTimeJst : null,
    );
  }

  /// Fake GET /v0/subjects/{id} response.
  Map<String, dynamic> toSubjectJson() {
    final int idNum = int.tryParse(subjectId.replaceAll(RegExp(r'\D'), '')) ?? 99999;
    return <String, dynamic>{
      'id': idNum,
      'name': title,
      'name_cn': title,
      'total_episodes': totalEpisodes,
      'eps': totalEpisodes,
      'rating': <String, dynamic>{
        'score': 7.5,
        'total': 100,
        'rank': 500,
        'count': <String, int>{
          for (int i = 1; i <= 10; i++) '$i': 10 - i + 1,
        },
      },
    };
  }

  /// Fake GET /v0/episodes?subject_id={id}&type=0 response data array.
  List<Map<String, dynamic>> toEpisodeListJson() {
    final int idBase = int.tryParse(subjectId.replaceAll(RegExp(r'\D'), '')) ?? 99999;

    return List<Map<String, dynamic>>.generate(totalEpisodes, (int i) {
      final int epNo = i + 1;
      final DateTime airdate = firstEpisodeAirdate.add(
        Duration(days: i * episodeIntervalDays),
      );
      final String dateStr =
          '${airdate.year.toString().padLeft(4, '0')}-'
          '${airdate.month.toString().padLeft(2, '0')}-'
          '${airdate.day.toString().padLeft(2, '0')}';
      return <String, dynamic>{
        'id': idBase * 100 + epNo,
        'type': 0,
        'sort': epNo,
        'ep': epNo,
        'airdate': dateStr,
        'name_cn': '第$epNo集',
        'name': 'Episode $epNo',
        'comment': math.max(0, 100 - epNo * 5),
        'duration': '24m',
        'desc': '',
        'disc': 0,
        'duration_seconds': 1440,
      };
    });
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subjectId': subjectId,
        'title': title,
        'weekdayJst': weekdayJst,
        'broadcastTimeJst': broadcastTimeJst,
        'firstEpisodeAirdate': firstEpisodeAirdate.toIso8601String(),
        'totalEpisodes': totalEpisodes,
        'apiUpdateDelayMinutes': apiUpdateDelayMinutes,
        'episodeIntervalDays': episodeIntervalDays,
      };

  factory SimulatedAnime.fromJson(Map<String, dynamic> json) {
    return SimulatedAnime(
      subjectId: json['subjectId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      weekdayJst: json['weekdayJst'] as String? ?? '',
      broadcastTimeJst: json['broadcastTimeJst'] as String? ?? '',
      firstEpisodeAirdate: DateTime.tryParse(
            json['firstEpisodeAirdate'] as String? ?? '',
          ) ??
          DateTime.now(),
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt() ?? 0,
      apiUpdateDelayMinutes:
          (json['apiUpdateDelayMinutes'] as num?)?.toInt() ?? 5,
      episodeIntervalDays:
          (json['episodeIntervalDays'] as num?)?.toInt() ?? 7,
    );
  }
}
