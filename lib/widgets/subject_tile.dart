import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/subject_item.dart';
import '../models/subject_progress.dart';

/// 柱状图位置与尺寸配置。
class EpisodeCommentChartLayout {
  const EpisodeCommentChartLayout({
    required this.alignment,
    required this.offsetX,
    required this.offsetY,
    required this.width,
    required this.height,
    required this.headerHeight,
    required this.headerBottomGap,
    required this.barGap,
    required this.minBarHeight,
    required this.backgroundRadius,
    required this.contentPaddingHorizontal,
    required this.contentPaddingVertical,
    required this.backgroundColor,
    required this.backgroundBorderColor,
  });

  final Alignment alignment;
  final double offsetX;
  final double offsetY;
  final double width;
  final double height;
  final double headerHeight;
  final double headerBottomGap;
  final double barGap;
  final double minBarHeight;
  final double backgroundRadius;
  final double contentPaddingHorizontal;
  final double contentPaddingVertical;
  final Color backgroundColor;
  final Color backgroundBorderColor;
}

/// 默认柱状图布局常量。
const EpisodeCommentChartLayout kDefaultCommentChartLayout =
    EpisodeCommentChartLayout(
  alignment: Alignment.centerRight,
  offsetX: 0,
  offsetY: 20,
  width: 250,
  height: 67,
  headerHeight: 16,
  headerBottomGap: 4,
  barGap: 2,
  minBarHeight: 2,
  backgroundRadius: 12,
  contentPaddingHorizontal: 10,
  contentPaddingVertical: 8,
  backgroundColor: Color(0x00000000),
  backgroundBorderColor: Color(0x00000000),
);

/// 封面占位组件。
Widget buildCoverPlaceholder({
  double width = 54,
  double height = 72,
  ColorScheme? colors,
}) {
  final Color bg = colors?.surfaceContainerHighest ?? Colors.transparent;
  final Color iconColor = colors?.onSurfaceVariant ?? Colors.grey;
  return Container(
    width: width,
    height: height,
    color: bg,
    child: Icon(
      Icons.movie_creation_outlined,
      size: 18,
      color: iconColor,
    ),
  );
}

/// 格式化学分字符串。
String formatProgressText(SubjectProgress? progress) {
  if (progress == null) return '进度: 未获取';
  if (progress.error != null && progress.error!.isNotEmpty) {
    return '进度获取失败: ${progress.error}';
  }
  final String latestCnTitle = (progress.latestAiredCnTitle ?? '').trim();
  final String latestAtLabel = (progress.latestAiredAtLabel ?? '').trim();
  final String latestText = progress.latestAiredEp != null
      ? '，最新已放送 EP${progress.latestAiredEp}'
          '${latestCnTitle.isNotEmpty ? '『$latestCnTitle』' : ''}'
          '${latestAtLabel.isNotEmpty ? '（$latestAtLabel）' : ''}'
      : '';
  return '进度: ${progress.progressText ?? '未知'}$latestText';
}

/// 格式化评分徽章文本。
String formatRatingBadgeText(SubjectProgress? progress) {
  final double? score = progress?.ratingScore;
  if (score == null || score <= 0) return '';
  return '评分 ${score.toStringAsFixed(1)}';
}

/// 番剧条目卡片组件 —— 用于今日更新、我的关注等列表。
class SubjectTile extends StatelessWidget {
  const SubjectTile({
    super.key,
    required this.item,
    required this.index,
    required this.followed,
    required this.progress,
    this.showCover = false,
    this.coverWidth = 54,
    this.coverHeight = 72,
    this.showFollowedBadge = false,
    this.highlightFollowed = false,
    this.updateWeekdayText = '',
    this.updateTimeText = '',
    this.showRatingBadge = false,
    this.showCommentChart = true,
    this.showCommentTotalBadge = false,
    this.chartLayout = kDefaultCommentChartLayout,
    this.hoveredSubjectId,
    this.hoveredBarIndex,
    this.onShowDetail,
    this.onToggleFollow,
    this.onAdjustProgress,
    this.onBarHover,
    this.onBarHoverEnd,
  });

  final SubjectItem item;
  final int index;
  final bool followed;
  final SubjectProgress? progress;
  final bool showCover;
  final double coverWidth;
  final double coverHeight;
  final bool showFollowedBadge;
  final bool highlightFollowed;
  final String updateWeekdayText;
  final String updateTimeText;
  final bool showRatingBadge;
  final bool showCommentChart;
  final bool showCommentTotalBadge;
  final EpisodeCommentChartLayout chartLayout;
  final String? hoveredSubjectId;
  final int? hoveredBarIndex;
  final VoidCallback? onShowDetail;
  final VoidCallback? onToggleFollow;
  final VoidCallback? onAdjustProgress;
  final void Function(String subjectId, int? barIndex)? onBarHover;
  final VoidCallback? onBarHoverEnd;

  String _formatProgress(SubjectProgress? p) {
    if (p == null) return '进度: 未获取';
    if (p.error != null && p.error!.isNotEmpty) return '进度获取失败: ${p.error}';
    final String latestCnTitle = (p.latestAiredCnTitle ?? '').trim();
    final String latestAtLabel = (p.latestAiredAtLabel ?? '').trim();
    final String latestText = p.latestAiredEp != null
        ? '，最新已放送 EP${p.latestAiredEp}'
            '${latestCnTitle.isNotEmpty ? '『$latestCnTitle』' : ''}'
            '${latestAtLabel.isNotEmpty ? '（$latestAtLabel）' : ''}'
        : '';
    return '进度: ${p.progressText ?? '未知'}$latestText';
  }

  String _formatRatingBadge(SubjectProgress? p) {
    final double? score = p?.ratingScore;
    if (score == null || score <= 0) return '';
    return '评分 ${score.toStringAsFixed(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final int totalCommentCount = progress == null
        ? 0
        : progress!.episodeCommentCounts.fold<int>(
            0, (int sum, int value) => sum + value);
    final String ratingText =
        showRatingBadge ? _formatRatingBadge(progress) : '';
    final bool isHighRating = (progress?.ratingScore ?? 0) >= 7.5;
    final String title = item.displayName.isNotEmpty
        ? item.displayName
        : item.subjectId;

    // Use theme-aware colors for the chart layout.
    final EpisodeCommentChartLayout effectiveChartLayout = chartLayout == kDefaultCommentChartLayout
        ? EpisodeCommentChartLayout(
            alignment: chartLayout.alignment,
            offsetX: chartLayout.offsetX,
            offsetY: chartLayout.offsetY,
            width: chartLayout.width,
            height: chartLayout.height,
            headerHeight: chartLayout.headerHeight,
            headerBottomGap: chartLayout.headerBottomGap,
            barGap: chartLayout.barGap,
            minBarHeight: chartLayout.minBarHeight,
            backgroundRadius: chartLayout.backgroundRadius,
            contentPaddingHorizontal: chartLayout.contentPaddingHorizontal,
            contentPaddingVertical: chartLayout.contentPaddingVertical,
            backgroundColor: colors.surface,
            backgroundBorderColor: colors.outlineVariant,
          )
        : chartLayout;

    final Color followedHighlightColor = isDark
        ? colors.secondaryContainer.withValues(alpha: 0.45)
        : const Color(0xFFFFF8D6);
    final Color followedBadgeBg = isDark
        ? colors.primaryContainer
        : const Color(0xFFFFD54F);
    final Color followedBadgeFg = isDark
        ? colors.onPrimaryContainer
        : const Color(0xFF5C3B00);
    final Color weekdayBadgeBg = isDark
        ? colors.tertiaryContainer
        : const Color(0xFFE8F5E9);
    final Color weekdayBadgeFg = isDark
        ? colors.onTertiaryContainer
        : const Color(0xFF1B5E20);
    final Color timeBadgeBg = isDark
        ? colors.secondaryContainer
        : const Color(0xFFE3F2FD);
    final Color timeBadgeFg = isDark
        ? colors.onSecondaryContainer
        : const Color(0xFF0D47A1);
    final Color highRatingBadgeBg = isDark
        ? colors.tertiaryContainer
        : const Color(0xFFFFEB3B);
    final Color highRatingBadgeFg = isDark
        ? colors.onTertiaryContainer
        : const Color(0xFFBF360C);
    final Color normalRatingBadgeBg = isDark
        ? colors.secondaryContainer
        : const Color(0xFFFFF3E0);
    final Color normalRatingBadgeFg = isDark
        ? colors.onSecondaryContainer
        : const Color(0xFFE65100);
    final Color commentTotalBg = isDark
        ? colors.surfaceContainerHighest
        : const Color(0xFFF3F4F6);
    final Color commentTotalBorder = isDark
        ? colors.outlineVariant
        : const Color(0xFFD1D5DB);
    final Color commentTotalFg = isDark
        ? colors.onSurfaceVariant
        : const Color(0xFF374151);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: highlightFollowed && followed ? followedHighlightColor : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (showCover)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onShowDetail,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.localCoverPath.isNotEmpty
                      ? Image.file(
                          File(item.localCoverPath),
                          width: coverWidth,
                          height: coverHeight,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stackTrace) =>
                              buildCoverPlaceholder(
                                width: coverWidth,
                                height: coverHeight,
                              ),
                        )
                      : buildCoverPlaceholder(
                          width: coverWidth,
                          height: coverHeight,
                        ),
                ),
              ),
            if (showCover) const SizedBox(width: 12),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: showCover ? coverHeight : 0,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    if (showCommentChart &&
                        progress != null &&
                        progress!.error == null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (BuildContext context, BoxConstraints box) {
                            final double chartWidth = effectiveChartLayout.width
                                .clamp(1.0, math.max(1.0, box.maxWidth))
                                .toDouble();
                            final double chartHeight = effectiveChartLayout.height
                                .clamp(1.0, math.max(1.0, box.maxHeight))
                                .toDouble();

                            final double freeWidth = math.max(
                              0, box.maxWidth - chartWidth,
                            );
                            final double freeHeight = math.max(
                              0, box.maxHeight - chartHeight,
                            );

                            final double anchorLeft =
                                ((effectiveChartLayout.alignment.x + 1) / 2) * freeWidth;
                            final double anchorTop =
                                ((effectiveChartLayout.alignment.y + 1) / 2) * freeHeight;

                            final double minOffsetX = -anchorLeft;
                            final double maxOffsetX = freeWidth - anchorLeft;
                            final double minOffsetY = -anchorTop;
                            final double maxOffsetY = freeHeight - anchorTop;

                            final double effectiveOffsetX = effectiveChartLayout.offsetX
                                .clamp(minOffsetX, maxOffsetX)
                                .toDouble();
                            final double effectiveOffsetY = effectiveChartLayout.offsetY
                                .clamp(minOffsetY, maxOffsetY)
                                .toDouble();

                            final double chartLeft = anchorLeft + effectiveOffsetX;
                            final double chartTop = anchorTop + effectiveOffsetY;

                            return Stack(
                              children: <Widget>[
                                Positioned(
                                  left: chartLeft,
                                  top: chartTop,
                                  width: chartWidth,
                                  height: chartHeight,
                                  child: _EpisodeCommentBarChart(
                                    counts: progress!.episodeCommentCounts,
                                    layout: effectiveChartLayout,
                                    subjectId: item.subjectId,
                                    hoveredSubjectId: hoveredSubjectId,
                                    hoveredBarIndex: hoveredBarIndex,
                                    onBarHover: onBarHover,
                                    onBarHoverEnd: onBarHoverEnd,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '$index. $title',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (followed && showFollowedBadge)
                              _badge(context, colors, '已关注',
                                  bg: followedBadgeBg, fg: followedBadgeFg),
                            if (updateWeekdayText.isNotEmpty)
                              _badge(context, colors, updateWeekdayText,
                                  bg: weekdayBadgeBg, fg: weekdayBadgeFg),
                            if (updateTimeText.isNotEmpty)
                              _badge(context, colors, updateTimeText,
                                  bg: timeBadgeBg, fg: timeBadgeFg),
                            if (ratingText.isNotEmpty)
                              _badge(context, colors, ratingText,
                                  bg: isHighRating
                                      ? highRatingBadgeBg
                                      : normalRatingBadgeBg,
                                  fg: isHighRating
                                      ? highRatingBadgeFg
                                      : normalRatingBadgeFg),
                            if (onToggleFollow != null) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: followed ? '取消关注' : '关注',
                                onPressed: onToggleFollow,
                                icon: Icon(
                                  followed
                                      ? Icons.playlist_remove_outlined
                                      : Icons.playlist_add_outlined,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (item.nameOrigin.isNotEmpty &&
                            item.nameOrigin != title)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '原名: ${item.nameOrigin}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          followed || progress != null
                              ? _formatProgress(progress)
                              : '进度: 未关注，不抓取',
                        ),
                        if (onAdjustProgress != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: onAdjustProgress,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.tune, size: 14),
                                label: const Text('修正更新进度'),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (showCommentTotalBadge)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: commentTotalBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: commentTotalBorder),
                          ),
                          child: Text(
                            '总评 $totalCommentCount',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: commentTotalFg,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, ColorScheme colors, String text,
      {required Color bg, required Color fg}) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: fg, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// 分集评论热度柱状图（内嵌到 SubjectTile 中）。
class _EpisodeCommentBarChart extends StatelessWidget {
  const _EpisodeCommentBarChart({
    required this.counts,
    required this.layout,
    required this.subjectId,
    this.hoveredSubjectId,
    this.hoveredBarIndex,
    this.onBarHover,
    this.onBarHoverEnd,
  });

  final List<int> counts;
  final EpisodeCommentChartLayout layout;
  final String subjectId;
  final String? hoveredSubjectId;
  final int? hoveredBarIndex;
  final void Function(String subjectId, int? barIndex)? onBarHover;
  final VoidCallback? onBarHoverEnd;

  @override
  Widget build(BuildContext context) {
    final List<int> values = counts
        .map((int value) => math.max(0, value))
        .toList(growable: false);
    final int maxCount =
        values.fold<int>(0, (int prev, int value) => math.max(prev, value));
    final double barsHeight =
        math.max(0, layout.height - layout.headerHeight - layout.headerBottomGap);
    final double barsWidth =
        math.max(0, layout.width - layout.contentPaddingHorizontal * 2);
    final int barCount = values.length;

    return MouseRegion(
      opaque: true,
      onExit: (_) {
        if (hoveredSubjectId != subjectId) return;
        onBarHoverEnd?.call();
      },
      onHover: (event) {
        int? index;
        if (barCount > 0) {
          final double barTop = layout.contentPaddingVertical +
              layout.headerHeight +
              layout.headerBottomGap;
          final double barBottom = barTop + barsHeight;
          final bool insideBarRegion =
              event.localPosition.dy >= barTop &&
                  event.localPosition.dy <= barBottom;

          if (insideBarRegion) {
            final double relativeX =
                (event.localPosition.dx - layout.contentPaddingHorizontal)
                    .clamp(0.0, barsWidth);
            final double maxGapByWidth =
                barCount <= 1 ? 0 : barsWidth / (barCount * 2);
            final double effectiveGap =
                math.min(layout.barGap, maxGapByWidth);
            final double totalGapWidth = effectiveGap * (barCount - 1);
            final double rawBarWidth =
                (barsWidth - totalGapWidth) / barCount;
            final double barWidth =
                rawBarWidth.isFinite && rawBarWidth > 0 ? rawBarWidth : 0;
            final double step = barWidth + effectiveGap;

            int computed =
                step <= 0 ? 0 : (relativeX / step).floor();
            if (computed < 0) computed = 0;
            if (computed >= barCount) computed = barCount - 1;
            index = computed;
          }
        }
        onBarHover?.call(subjectId, index);
      },
      child: Container(
        width: layout.width,
        height: layout.height,
        padding: EdgeInsets.symmetric(
          horizontal: layout.contentPaddingHorizontal,
          vertical: layout.contentPaddingVertical,
        ),
        decoration: BoxDecoration(
          color: layout.backgroundColor,
          borderRadius: BorderRadius.circular(layout.backgroundRadius),
          border: Border.all(color: layout.backgroundBorderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: layout.headerHeight,
              child: Row(
                children: <Widget>[
                  Text('分集评论热度',
                      style: Theme.of(context).textTheme.labelSmall),
                  const Spacer(),
                  Text(
                    maxCount > 0 ? '峰值 $maxCount' : '峰值 -',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: layout.headerBottomGap),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double chartBarsHeight =
                      math.max(0, constraints.maxHeight);
                  if (values.isEmpty) {
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: constraints.maxWidth,
                        height: layout.minBarHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }

                  final int barCount = values.length;
                  final double maxGapByWidth = barCount <= 1
                      ? 0
                      : constraints.maxWidth / (barCount * 2);
                  final double effectiveGap =
                      math.min(layout.barGap, maxGapByWidth);
                  final double totalGapWidth = effectiveGap * (barCount - 1);
                  final double rawBarWidth =
                      (constraints.maxWidth - totalGapWidth) / barCount;
                  final double barWidth = rawBarWidth.isFinite && rawBarWidth > 0
                      ? rawBarWidth
                      : 0;

                  final bool isHovered = hoveredSubjectId == subjectId;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List<Widget>.generate(barCount, (int i) {
                          final int value = values[i];
                          final double ratio = maxCount <= 0
                              ? 0.08
                              : value <= 0
                                  ? 0.08
                                  : value / maxCount;
                          final Color baseColor =
                              Theme.of(context).colorScheme.primary;
                          final Color color = Color.lerp(
                                baseColor.withValues(alpha: 0.25),
                                baseColor,
                                ratio.clamp(0.0, 1.0),
                              ) ??
                              baseColor;
                          final double cellWidth =
                              barWidth + (i == barCount - 1 ? 0 : effectiveGap);

                          return SizedBox(
                            width: cellWidth,
                            height: chartBarsHeight,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: barWidth,
                                height: math.max(
                                  layout.minBarHeight,
                                  chartBarsHeight * ratio,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      if (isHovered &&
                          hoveredBarIndex != null &&
                          hoveredBarIndex! >= 0 &&
                          hoveredBarIndex! < barCount)
                        Positioned(
                          top: -24,
                          left: (() {
                            final double step = barWidth + effectiveGap;
                            final double center =
                                hoveredBarIndex! * step + barWidth / 2;
                            const double labelWidth = 76;
                            return (center - labelWidth / 2)
                                .clamp(0.0,
                                    math.max(0.0, constraints.maxWidth - labelWidth))
                                .toDouble();
                          })(),
                          child: IgnorePointer(
                            child: Container(
                              width: 76,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.inverseSurface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '评论 ${values[hoveredBarIndex!]}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onInverseSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
