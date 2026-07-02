import '../constants.dart';

/// BGMLIST 放送时刻提示
class BroadcastScheduleHint {
  const BroadcastScheduleHint({required this.weekday, required this.time});

  final String weekday;
  final String time;
}

/// 转换后的周几+时间
class ConvertedWeekdayTime {
  const ConvertedWeekdayTime({required this.weekday, required this.time});

  final String weekday;
  final String time;
}

/// BGMLIST OnAir JSON 条目
class BgmListOnAirEntry {
  const BgmListOnAirEntry({required this.timeJst, required this.jpTitles});

  final String timeJst;
  final List<String> jpTitles;
}

/// BGMLIST 用于构建周历的候选条目
class BgmListScheduleCandidate {
  const BgmListScheduleCandidate({
    required this.subjectId,
    required this.subjectUrl,
    required this.titleJp,
    required this.titleCn,
    required this.coverUrl,
    required this.weekdayJst,
    required this.updateTimeJst,
    required this.beginJst,
    required this.periodDays,
  });

  final String subjectId;
  final String subjectUrl;
  final String titleJp;
  final String titleCn;
  final String coverUrl;
  final String weekdayJst;
  final String updateTimeJst;
  final DateTime beginJst;
  final int periodDays;
}

/// 时区转换工具
class BroadcastTimeConverter {
  static const int jstOffsetMinutes = 9 * 60;
  static const int minTimezoneOffsetMinutes = -12 * 60;
  static const int maxTimezoneOffsetMinutes = 14 * 60;

  static int normalizeTimezoneOffsetMinutes(int value) {
    return value.clamp(minTimezoneOffsetMinutes, maxTimezoneOffsetMinutes);
  }

  static String formatUtcOffsetLabel(int offsetMinutes) {
    final int normalized = normalizeTimezoneOffsetMinutes(offsetMinutes);
    final String sign = normalized >= 0 ? '+' : '-';
    final int absMinutes = normalized.abs();
    final int hour = absMinutes ~/ 60;
    final int minute = absMinutes % 60;
    if (minute == 0) {
      return 'UTC$sign$hour';
    }
    return 'UTC$sign$hour:${minute.toString().padLeft(2, '0')}';
  }

  static int? weekdayToIndex(String weekdayText) {
    final String value = weekdayText.trim();
    if (value.isEmpty) {
      return null;
    }
    for (final MapEntry<int, String> entry in weekdayMap.entries) {
      if (entry.value == value) {
        return entry.key;
      }
    }
    return null;
  }

  static String weekdayFromIndex(int index) {
    final int wrapped = wrapWeekday(index);
    return weekdayMap[wrapped] ?? '星期一';
  }

  static int? parseClockMinutes(String timeText, {int maxHour = 47}) {
    final RegExpMatch? match = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(timeText.trim());
    if (match == null) {
      return null;
    }
    final int? hour = int.tryParse(match.group(1) ?? '');
    final int? minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > maxHour || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  static String formatClockMinutes(int minutes) {
    final int normalized = positiveMod(minutes, 24 * 60);
    final int hour = normalized ~/ 60;
    final int minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static ConvertedWeekdayTime? convertWeekdayAndTime({
    required String weekday,
    required String time,
    required int fromOffsetMinutes,
    required int toOffsetMinutes,
  }) {
    final int? weekdayIndex = weekdayToIndex(weekday);
    final int? sourceMinutes = parseClockMinutes(time);
    if (weekdayIndex == null || sourceMinutes == null) {
      return null;
    }

    final int normalizedFrom = normalizeTimezoneOffsetMinutes(fromOffsetMinutes);
    final int normalizedTo = normalizeTimezoneOffsetMinutes(toOffsetMinutes);

    final int sourceDayCarry = sourceMinutes ~/ (24 * 60);
    final int sourceMinuteInDay = positiveMod(sourceMinutes, 24 * 60);
    final int sourceWeekday = wrapWeekday(weekdayIndex + sourceDayCarry);
    final int delta = normalizedTo - normalizedFrom;

    final int targetAbsolute = sourceMinuteInDay + delta;
    final int targetDayCarry = floorDiv(targetAbsolute, 24 * 60);
    final int targetMinuteInDay = positiveMod(targetAbsolute, 24 * 60);
    final int targetWeekday = wrapWeekday(sourceWeekday + targetDayCarry);

    return ConvertedWeekdayTime(
      weekday: weekdayFromIndex(targetWeekday),
      time: formatClockMinutes(targetMinuteInDay),
    );
  }

  static DateTime? resolveEpisodeBroadcastInDisplayTime({
    required DateTime airdateJst,
    required String displayTime,
    required int displayOffsetMinutes,
    String displayWeekday = '',
  }) {
    final int? displayMinutesRaw = parseClockMinutes(displayTime);
    if (displayMinutesRaw == null) {
      return null;
    }

    final int normalizedDisplayOffset = normalizeTimezoneOffsetMinutes(
      displayOffsetMinutes,
    );
    final int displayDayCarry = displayMinutesRaw ~/ (24 * 60);
    final int displayMinuteInDay = positiveMod(displayMinutesRaw, 24 * 60);

    final int jstAbsolute =
        displayMinuteInDay + (jstOffsetMinutes - normalizedDisplayOffset);
    final int jstDayCarry = displayDayCarry + floorDiv(jstAbsolute, 24 * 60);
    final int jstMinuteInDay = positiveMod(jstAbsolute, 24 * 60);

    final DateTime jstDate = DateTime.utc(
      airdateJst.year,
      airdateJst.month,
      airdateJst.day,
    ).add(Duration(days: jstDayCarry));
    final DateTime jstMomentUtc = jstDate.add(
      Duration(minutes: jstMinuteInDay - jstOffsetMinutes),
    );
    DateTime displayMoment = jstMomentUtc.add(
      Duration(minutes: normalizedDisplayOffset),
    );

    final int? expectedWeekday = weekdayToIndex(displayWeekday);
    if (expectedWeekday == null) {
      return displayMoment;
    }

    final int forward = (expectedWeekday - displayMoment.weekday + 7) % 7;
    final int backward = forward - 7;
    final int shiftDays =
        forward.abs() <= backward.abs() ? forward : backward;
    displayMoment = displayMoment.add(Duration(days: shiftDays));
    return displayMoment;
  }
}
