import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/subject_item.dart';
import '../models/subject_progress.dart';
import '../widgets/subject_tile.dart';

/// Parses a "HH:MM" time string into total minutes since midnight, returning
/// a sentinel past 24:00 for invalid / unrecognized formats.
///
/// Matches the exact same semantics as the original [_parseUpdateTimeMinutes]
/// method on [_BangumiHomePageState].
int _parseUpdateTimeMinutes(String text) =>
    parseUpdateTimeMinutes(text);

/// Standalone tab that displays today's schedule items, split into followed
/// (watchlist) and unfollowed groups, sorted by update time.
///
/// Extracted from [BangumiHomePage._buildTodayTab] to reduce coupling and
/// file size of main.dart.
class TodayTab extends StatelessWidget {
  const TodayTab({
    super.key,
    required this.isLoadingSchedule,
    required this.scheduleError,
    required this.todayItems,
    required this.watchIds,
    required this.progressCache,
    required this.effectiveTodayWeekday,
    required this.timezoneLabel,
    required this.onShowDetail,
    required this.onToggleFollow,
  });

  /// Whether the schedule is still being loaded.
  final bool isLoadingSchedule;

  /// Non-empty when the schedule fetch failed.
  final String scheduleError;

  /// Subject items whose broadcast weekday matches "today".
  final List<SubjectItem> todayItems;

  /// Set of subject IDs currently in the watchlist.
  final Set<String> watchIds;

  /// Per-subject progress snapshots keyed by subject ID.
  final Map<String, SubjectProgress> progressCache;

  /// The resolved weekday label for "today" (e.g. "星期一").
  final String effectiveTodayWeekday;

  /// Display label for the current timezone (e.g. "UTC+08:00").
  final String timezoneLabel;

  /// Called when the user taps the detail button on a subject tile.
  final ValueChanged<SubjectItem> onShowDetail;

  /// Called when the user taps the follow/unfollow button on a subject tile.
  final ValueChanged<SubjectItem> onToggleFollow;

  @override
  Widget build(BuildContext context) {
    if (isLoadingSchedule) {
      return const Center(child: CircularProgressIndicator());
    }
    if (scheduleError.isNotEmpty) {
      return Center(child: Text('获取失败: $scheduleError'));
    }

    final List<SubjectItem> followedItems = todayItems
        .where((SubjectItem item) => watchIds.contains(item.subjectId))
        .toList();
    final List<SubjectItem> unfollowedItems = todayItems
        .where((SubjectItem item) => !watchIds.contains(item.subjectId))
        .toList();

    // Local sort comparator: primary key is update time (HH:MM), secondary
    // key is the display name.
    int compareByUpdateTime(SubjectItem a, SubjectItem b) {
      final int aMinutes = _parseUpdateTimeMinutes(a.updateTime);
      final int bMinutes = _parseUpdateTimeMinutes(b.updateTime);
      final int timeCompare = aMinutes.compareTo(bMinutes);
      if (timeCompare != 0) {
        return timeCompare;
      }

      final String aName =
          a.displayName.isNotEmpty ? a.displayName : a.subjectId;
      final String bName =
          b.displayName.isNotEmpty ? b.displayName : b.subjectId;
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    }

    followedItems.sort(compareByUpdateTime);
    unfollowedItems.sort(compareByUpdateTime);

    final List<SubjectItem> displayItems = <SubjectItem>[
      ...followedItems,
      ...unfollowedItems,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '今天是 $effectiveTodayWeekday，今日更新 ${todayItems.length} 部。',
              ),
              Text('当前时区: $timezoneLabel'),
              const SizedBox(height: 4),
            ],
          ),
        ),
        Expanded(
          child: displayItems.isEmpty
              ? const Center(child: Text('今日无数据'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: displayItems.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SubjectItem item = displayItems[index];
                    final bool followed = watchIds.contains(item.subjectId);
                    return SubjectTile(
                      item: item,
                      index: index + 1,
                      followed: followed,
                      progress: progressCache[item.subjectId],
                      showCover: true,
                      coverWidth: 72,
                      coverHeight: 96,
                      showFollowedBadge: true,
                      highlightFollowed: true,
                      updateTimeText: item.updateTime,
                      showRatingBadge: true,
                      showCommentChart: false,
                      showCommentTotalBadge: true,
                      onShowDetail: () => onShowDetail(item),
                      onToggleFollow: () => onToggleFollow(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
