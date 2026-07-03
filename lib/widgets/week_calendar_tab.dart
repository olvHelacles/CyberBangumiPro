import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/subject_item.dart';

/// Parses a "HH:MM" time string into total minutes since midnight, returning
/// a sentinel past 24:00 for invalid / unrecognized formats.
int _parseUpdateTimeMinutes(String text) {
  final RegExpMatch? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (match == null) {
    return 24 * 60 + 1;
  }

  final int hour = int.tryParse(match.group(1) ?? '') ?? 99;
  final int minute = int.tryParse(match.group(2) ?? '') ?? 99;
  if (hour < 0 || hour > 29 || minute < 0 || minute > 59) {
    return 24 * 60 + 1;
  }
  return hour * 60 + minute;
}

/// Standalone placeholder for week calendar cover entries (108x146).
Widget _buildWeekCalendarPlaceholder(BuildContext context) {
  return Container(
    width: 108,
    height: 146,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.movie_creation_outlined,
      size: 22,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// Builds an individual week calendar entry card (cover + time badge + follow
/// toggle).
Widget _buildWeekCalendarEntry({
  required BuildContext context,
  required SubjectItem item,
  required bool followed,
  required ValueChanged<SubjectItem> onShowDetail,
  required ValueChanged<SubjectItem> onToggleFollow,
}) {
  final String title = item.displayName.isNotEmpty
      ? item.displayName
      : (item.nameOrigin.isNotEmpty ? item.nameOrigin : item.subjectId);
  final String timeText = item.updateTime;
  final ColorScheme colors = Theme.of(context).colorScheme;
  final bool canToggleFollow = item.subjectId.isNotEmpty;

  return Container(
    width: 108,
    margin: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GestureDetector(
          onTap: () => onShowDetail(item),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: <Widget>[
                  item.localCoverPath.isNotEmpty
                      ? Image.file(
                          File(item.localCoverPath),
                          width: 108,
                          height: 146,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stackTrace) =>
                              _buildWeekCalendarPlaceholder(context),
                        )
                      : item.coverUrl.isNotEmpty
                      ? _buildWeekCalendarPlaceholder(context)
                      : _buildWeekCalendarPlaceholder(context),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            Colors.transparent,
                            colors.scrim.withValues(alpha: 0.28),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (timeText.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          timeText,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  if (canToggleFollow)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: colors.surfaceContainerHigh.withValues(
                          alpha: 0.76,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onToggleFollow(item),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              followed
                                  ? Icons.playlist_remove_outlined
                                  : Icons.playlist_add_outlined,
                              size: 16,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

/// Standalone tab that displays a week calendar grid (7-day column layout)
/// grouped by weekday, sorted by update time.
///
/// Extracted from [BangumiHomePage._buildWeekCalendarTab] to reduce coupling
/// and file size of main.dart.
class WeekCalendarTab extends StatelessWidget {
  const WeekCalendarTab({
    super.key,
    required this.scheduleData,
    required this.watchIds,
    required this.showAll,
    required this.timezoneLabel,
    required this.watchById,
    required this.onShowDetail,
    required this.onToggleFollow,
    required this.onShowAllChanged,
  });

  /// Raw schedule data fetched from the calendar API.
  final List<DaySchedule> scheduleData;

  /// Set of subject IDs that the user is currently following.
  final Set<String> watchIds;

  /// Whether the calendar shows all items (true) or only followed ones (false).
  final bool showAll;

  /// Human-readable timezone label (e.g. "UTC+9" or "UTC+8").
  final String timezoneLabel;

  /// Map from subject ID to the watchlist [SubjectItem], used to fill in
  /// missing metadata (cover, update time) from schedule items.
  final Map<String, SubjectItem> watchById;

  /// Called when the user taps a calendar entry to view details.
  final ValueChanged<SubjectItem> onShowDetail;

  /// Called when the user taps the follow/unfollow toggle on an entry.
  final ValueChanged<SubjectItem> onToggleFollow;

  /// Called when the user flips the "show all / followed only" switch.
  final ValueChanged<bool> onShowAllChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    final List<String> orderedWeekdays = <String>[
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日',
    ];
    final DateTime now = DateTime.now();
    final String todayWeekday = weekdayMap[now.weekday] ?? '';

    final Map<String, List<SubjectItem>> grouped = <String, List<SubjectItem>>{
      for (final String day in orderedWeekdays) day: <SubjectItem>[],
    };

    for (final DaySchedule day in scheduleData) {
      final String weekday = day.weekday;
      if (!grouped.containsKey(weekday)) {
        continue;
      }

      for (final SubjectItem item in day.items) {
        if (!showAll && !watchIds.contains(item.subjectId)) {
          continue;
        }
        final SubjectItem? fromWatch = watchById[item.subjectId];
        grouped[weekday]!.add(
          item.copyWith(
            coverUrl: item.coverUrl.isNotEmpty
                ? item.coverUrl
                : (fromWatch?.coverUrl ?? ''),
            localCoverPath: fromWatch?.localCoverPath ?? item.localCoverPath,
            updateTime: item.updateTime.isNotEmpty
                ? item.updateTime
                : (fromWatch?.updateTime ?? ''),
          ),
        );
      }
    }

    for (final String day in orderedWeekdays) {
      grouped[day]!.sort((SubjectItem a, SubjectItem b) {
        final int t1 = _parseUpdateTimeMinutes(a.updateTime);
        final int t2 = _parseUpdateTimeMinutes(b.updateTime);
        if (t1 != t2) {
          return t1.compareTo(t2);
        }
        return a.displayName.compareTo(b.displayName);
      });
    }

    final int totalCount = grouped.values.fold<int>(
      0,
      (int sum, List<SubjectItem> items) => sum + items.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: <Widget>[
              Switch(
                value: showAll,
                onChanged: onShowAllChanged,
              ),
              const SizedBox(width: 8),
              Text(
                '${showAll ? '全量显示' : '已关注'}（$timezoneLabel）',
              ),
            ],
          ),
        ),
        Expanded(
          child: totalCount == 0
              ? Center(
                  child: Text(
                    showAll
                        ? '周历暂无可展示数据，请先刷新日历'
                        : watchIds.isEmpty
                        ? '当前没有关注番剧，可打开全量显示查看全部'
                        : '关注周历暂无可展示数据，请先刷新日历',
                  ),
                )
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    const double columnWidth = 124;
                    const double dividerWidth = 1;
                    const double sidePadding = 12;
                    final double contentWidth =
                        orderedWeekdays.length * columnWidth +
                        (orderedWeekdays.length + 1) * dividerWidth;
                    final double viewportWidth = math.max(
                      0,
                      constraints.maxWidth - sidePadding * 2,
                    );

                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          child: SizedBox(
                            width: math.max(contentWidth, viewportWidth),
                            child: IntrinsicHeight(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List<Widget>.generate(
                                  orderedWeekdays.length * 2 + 1,
                                  (int i) {
                                    if (i.isEven) {
                                      return Container(
                                        width: dividerWidth,
                                        color: colors.outlineVariant,
                                      );
                                    }

                                    final int index = (i - 1) ~/ 2;
                                    final String day = orderedWeekdays[index];
                                    final List<SubjectItem> items =
                                        grouped[day]!;
                                    final bool isTodayColumn =
                                        day == todayWeekday;

                                    return SizedBox(
                                      width: columnWidth,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          8,
                                          10,
                                          8,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              day,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color: isTodayColumn
                                                        ? colors.primary
                                                        : colors.onSurface,
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${items.length} 部',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (items.isEmpty)
                                              Text(
                                                '暂无更新',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                    ),
                                              )
                                            else
                                              ...items.map((
                                                SubjectItem entry,
                                              ) {
                                                final bool followed = watchIds
                                                    .contains(entry.subjectId);
                                                return _buildWeekCalendarEntry(
                                                  context: context,
                                                  item: entry,
                                                  followed: followed,
                                                  onShowDetail: onShowDetail,
                                                  onToggleFollow: onToggleFollow,
                                                );
                                              }),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
