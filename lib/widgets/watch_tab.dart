import 'package:flutter/material.dart';

import '../models/subject_item.dart';
import '../models/subject_progress.dart';
import '../widgets/subject_tile.dart';

/// 关注 Tab：在追（周历中）与补番（周历外）分档显示。
class WatchTab extends StatefulWidget {
  const WatchTab({
    super.key,
    required this.watchlist,
    required this.scheduleData,
    required this.progressCache,
    required this.timezoneLabel,
    required this.calendarIds,
    required this.catchUpProgress,
    required this.catchUpTotalEps,
    required this.catchUpTitles,
    required this.watchlistLastUpdated,
    required this.onShowDetail,
    required this.onToggleFollow,
    required this.onAdjustProgress,
    required this.onArchive,
    required this.onCatchUpForward,
    required this.onCatchUpBack,
  });

  final List<SubjectItem> watchlist;
  final List<DaySchedule> scheduleData;
  final Map<String, SubjectProgress> progressCache;
  final String timezoneLabel;
  final Set<String> calendarIds;
  final Map<String, int> catchUpProgress;
  final Map<String, int> catchUpTotalEps;
  final Map<String, Map<int, String>> catchUpTitles;
  final Map<String, DateTime> watchlistLastUpdated;
  final ValueChanged<SubjectItem> onShowDetail;
  final ValueChanged<SubjectItem> onToggleFollow;
  final ValueChanged<SubjectItem> onAdjustProgress;
  final ValueChanged<SubjectItem> onArchive;
  final ValueChanged<String> onCatchUpForward;
  final ValueChanged<String> onCatchUpBack;

  @override
  State<WatchTab> createState() => _WatchTabState();
}

class _WatchTabState extends State<WatchTab> {
  bool _showAiring = true;
  List<SubjectItem> _displayItems = <SubjectItem>[];
  bool _sortFrozen = false;

  List<SubjectItem> _computeDisplayItems() {
    final List<SubjectItem> items = widget.watchlist
        .where((SubjectItem item) {
          final bool inCalendar =
              widget.calendarIds.contains(item.subjectId);
          return _showAiring ? inCalendar : !inCalendar;
        })
        .toList();
    items.sort((SubjectItem a, SubjectItem b) {
      final DateTime? aAt =
          widget.watchlistLastUpdated[a.subjectId];
      final DateTime? bAt =
          widget.watchlistLastUpdated[b.subjectId];
      if (aAt == null && bAt == null) return 0;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return bAt.compareTo(aAt);
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (_sortFrozen) {
      _sortFrozen = false;
    } else {
      _displayItems = _computeDisplayItems();
    }

    final List<SubjectItem> filtered = _displayItems;

    final Map<String, String> weekdayBySubjectId = <String, String>{};
    final Map<String, String> updateTimeBySubjectId = <String, String>{};
    for (final DaySchedule day in widget.scheduleData) {
      for (final SubjectItem item in day.items) {
        if (item.subjectId.isEmpty) continue;
        weekdayBySubjectId.putIfAbsent(item.subjectId, () => day.weekday);
        if (item.updateTime.isNotEmpty) {
          updateTimeBySubjectId.putIfAbsent(
              item.subjectId, () => item.updateTime);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: <Widget>[
              Text(
                '关注番剧共 ${widget.watchlist.length} 部（${widget.timezoneLabel}）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: true, label: Text('追番')),
                  ButtonSegment<bool>(value: false, label: Text('补番')),
                ],
                selected: <bool>{_showAiring},
                onSelectionChanged: (Set<bool> selected) {
                  setState(() {
                    _showAiring = selected.first;
                    _displayItems = _computeDisplayItems();
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _showAiring
                        ? '当前没有在追番剧'
                        : '当前没有补番番剧',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: filtered.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SubjectItem item = filtered[index];
                    final String weekdayText =
                        weekdayBySubjectId[item.subjectId] ?? '';
                    final String timeText =
                        updateTimeBySubjectId[item.subjectId] ??
                        item.updateTime;
                    final int? catchUpEp = _showAiring
                        ? null
                        : (widget.catchUpProgress[item.subjectId] ?? 0);
                    return SubjectTile(
                      item: item,
                      index: index + 1,
                      followed: true,
                      progress: widget.progressCache[item.subjectId],
                      catchUpEpisode: catchUpEp,
                      catchUpTitle: catchUpEp != null && catchUpEp > 0
                          ? (widget.catchUpTitles[item.subjectId]
                                  ?[catchUpEp] ??
                              widget.progressCache[item.subjectId]
                                  ?.episodeTitleByEp[catchUpEp])
                          : null,
                      catchUpTotal: widget.catchUpTotalEps[item.subjectId],
                      showCover: true,
                      coverWidth: 84,
                      coverHeight: 112,
                      showFollowedBadge: false,
                      updateWeekdayText: weekdayText,
                      updateTimeText: timeText,
                      showRatingBadge: !_showAiring,
                      showCommentChart: _showAiring,
                      onShowDetail: () => widget.onShowDetail(item),
                      onToggleFollow: () => widget.onToggleFollow(item),
                      onAdjustProgress: _showAiring ? () => widget.onAdjustProgress(item) : null,
                      onArchive: () => widget.onArchive(item),
                      onEpisodeForward: _showAiring
                          ? null
                          : () {
                              _sortFrozen = true;
                              widget.onCatchUpForward(
                                  item.subjectId);
                            },
                      onEpisodeBack: _showAiring
                          ? null
                          : () {
                              _sortFrozen = true;
                              widget.onCatchUpBack(
                                  item.subjectId);
                            },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
