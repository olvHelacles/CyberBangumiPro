import 'package:flutter/material.dart';

import '../models/subject_item.dart';
import '../models/subject_progress.dart';
import '../widgets/subject_tile.dart';

class WatchTab extends StatelessWidget {
  const WatchTab({
    super.key,
    required this.watchlist,
    required this.scheduleData,
    required this.progressCache,
    required this.timezoneLabel,
    required this.onShowDetail,
    required this.onAdjustProgress,
  });

  final List<SubjectItem> watchlist;
  final List<DaySchedule> scheduleData;
  final Map<String, SubjectProgress> progressCache;
  final String timezoneLabel;
  final ValueChanged<SubjectItem> onShowDetail;
  final ValueChanged<SubjectItem> onAdjustProgress;

  @override
  Widget build(BuildContext context) {
    final Map<String, String> weekdayBySubjectId = <String, String>{};
    final Map<String, String> updateTimeBySubjectId = <String, String>{};

    for (final DaySchedule day in scheduleData) {
      for (final SubjectItem item in day.items) {
        if (item.subjectId.isEmpty) {
          continue;
        }
        if (!weekdayBySubjectId.containsKey(item.subjectId)) {
          weekdayBySubjectId[item.subjectId] = day.weekday;
        }
        if (item.updateTime.isNotEmpty &&
            !updateTimeBySubjectId.containsKey(item.subjectId)) {
          updateTimeBySubjectId[item.subjectId] = item.updateTime;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text('关注番剧共 ${watchlist.length} 部（$timezoneLabel）。'),
        ),
        Expanded(
          child: watchlist.isEmpty
              ? const Center(child: Text('当前没有关注番剧'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: watchlist.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SubjectItem item = watchlist[index];
                    final String weekdayText =
                        weekdayBySubjectId[item.subjectId] ?? '';
                    final String timeText =
                        updateTimeBySubjectId[item.subjectId] ??
                        item.updateTime;
                    return SubjectTile(
                      item: item,
                      index: index + 1,
                      followed: true,
                      progress: progressCache[item.subjectId],
                      showCover: true,
                      coverWidth: 72,
                      coverHeight: 96,
                      showFollowedBadge: false,
                      updateWeekdayText: weekdayText,
                      updateTimeText: timeText,
                      showRatingBadge: true,
                      onShowDetail: () => onShowDetail(item),
                      onAdjustProgress: () => onAdjustProgress(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
