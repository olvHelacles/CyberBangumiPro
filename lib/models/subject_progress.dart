import 'package:flutter/painting.dart';

/// 条目进度（来自 Bangumi API）
class SubjectProgress {
  const SubjectProgress({
    this.totalEpsDeclared,
    this.totalEpsListed,
    this.airedEps,
    this.latestAiredEp,
    this.latestAiredCnTitle,
    this.nextEp,
    this.ratingScore,
    this.episodeCommentCounts = const <int>[],
    this.episodeTitleByEp = const <int, String>{},
    this.progressText,
    this.latestAiredAtLabel,
    this.error,
  });

  final int? totalEpsDeclared;
  final int? totalEpsListed;
  final int? airedEps;
  final int? latestAiredEp;
  final String? latestAiredCnTitle;
  final int? nextEp;
  final double? ratingScore;
  final List<int> episodeCommentCounts;
  final Map<int, String> episodeTitleByEp;
  final String? progressText;
  final String? latestAiredAtLabel;
  final String? error;
}

/// 条目基本信息（来自 Bangumi 页面）
class SubjectBasicInfo {
  const SubjectBasicInfo({
    this.totalEpsDeclared,
    this.airStart = '',
    this.airWeekday = '',
  });

  final int? totalEpsDeclared;
  final String airStart;
  final String airWeekday;
}

/// 分集进度（来自 Bangumi 页面）
class EpisodeProgress {
  const EpisodeProgress({
    required this.totalEpsListed,
    required this.airedEps,
    this.latestAiredEp,
    this.latestAiredEpId,
    this.latestAiredOriginTitle,
    this.nextEp,
  });

  final int totalEpsListed;
  final int airedEps;
  final int? latestAiredEp;
  final String? latestAiredEpId;
  final String? latestAiredOriginTitle;
  final int? nextEp;
}

/// 评论柱状图布局参数
class EpisodeCommentChartLayout {
  const EpisodeCommentChartLayout({
    this.alignment = Alignment.centerRight,
    this.offsetX = 0,
    this.offsetY = 0,
    this.width = 300,
    this.height = 52,
    this.headerHeight = 16,
    this.headerBottomGap = 4,
    this.barGap = 2,
    this.minBarHeight = 2,
    this.backgroundRadius = 12,
    this.contentPaddingHorizontal = 10,
    this.contentPaddingVertical = 8,
    this.backgroundColor = const Color(0x00000000),
    this.backgroundBorderColor = const Color(0x00000000),
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
