import 'package:flutter/material.dart';

/// Top-right overlay showing progress bars for cover caching and progress
/// refresh tasks.
class ProgressOverlay extends StatelessWidget {
  const ProgressOverlay({
    super.key,
    required this.showStatusText,
    required this.statusText,
    required this.isCachingCalendarCovers,
    required this.calendarCoverCacheDone,
    required this.calendarCoverCacheTotal,
    required this.isLoadingProgress,
    required this.progressRefreshDone,
    required this.progressRefreshTotal,
  });

  final bool showStatusText;
  final String statusText;
  final bool isCachingCalendarCovers;
  final int calendarCoverCacheDone;
  final int calendarCoverCacheTotal;
  final bool isLoadingProgress;
  final int progressRefreshDone;
  final int progressRefreshTotal;

  @override
  Widget build(BuildContext context) {
    final bool showCoverProgress =
        isCachingCalendarCovers && calendarCoverCacheTotal > 0;
    final bool showRefreshProgress =
        isLoadingProgress && progressRefreshTotal > 0;

    if (!showStatusText && !showCoverProgress && !showRefreshProgress) {
      return const SizedBox.shrink();
    }

    final double coverValue = calendarCoverCacheTotal > 0
        ? (calendarCoverCacheDone / calendarCoverCacheTotal).clamp(0, 1)
        : 0;
    final double refreshValue = progressRefreshTotal > 0
        ? (progressRefreshDone / progressRefreshTotal).clamp(0, 1)
        : 0;

    return Align(
      alignment: Alignment.topRight,
      child: IgnorePointer(
        child: Container(
          width: 240,
          margin: const EdgeInsets.only(top: 8, right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showStatusText)
                Flexible(
                  flex: 6,
                  child: Text(
                    statusText,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (showStatusText && (showCoverProgress || showRefreshProgress))
                const SizedBox(width: 8),
              if (showCoverProgress || showRefreshProgress)
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (showCoverProgress)
                        LinearProgressIndicator(
                          value: coverValue,
                          minHeight: 3,
                        ),
                      if (showCoverProgress && showRefreshProgress)
                        const SizedBox(height: 4),
                      if (showRefreshProgress)
                        LinearProgressIndicator(
                          value: refreshValue,
                          minHeight: 3,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
