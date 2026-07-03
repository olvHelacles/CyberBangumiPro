import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../models/subject_item.dart';
import '../services/bangumi_service.dart';
import '../stores/cover_cache_manager.dart';

/// 条目详情底部弹窗内容。
class SubjectDetailSheet extends StatefulWidget {
  const SubjectDetailSheet({
    super.key,
    required this.subjectId,
    required this.item,
    required this.service,
    required this.coverCacheManager,
    required this.onOpenInBrowser,
    required this.onToggleFollow,
    required this.isFollowed,
  });

  final String subjectId;
  final SubjectItem item;
  final BangumiService service;
  final CoverCacheManager coverCacheManager;
  final VoidCallback onOpenInBrowser;
  final VoidCallback onToggleFollow;
  final bool isFollowed;

  @override
  State<SubjectDetailSheet> createState() => _SubjectDetailSheetState();
}

class _SubjectDetailSheetState extends State<SubjectDetailSheet> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  String? _localCoverPath;
  bool _summaryExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final Map<String, dynamic>? data =
          await widget.service.fetchSubjectFromApi(widget.subjectId);
      if (!mounted) return;

      if (data == null) {
        setState(() {
          _error = '获取条目信息失败';
          _loading = false;
        });
        return;
      }

      // 缓存封面
      String? coverUrl;
      final dynamic images = data['images'];
      if (images is Map<String, dynamic>) {
        coverUrl = (images['large'] ?? images['common'] ?? images['medium'] ?? '').toString();
      }
      if ((coverUrl == null || coverUrl.isEmpty) && widget.item.coverUrl.isNotEmpty) {
        coverUrl = widget.item.coverUrl;
      }

      String? localPath;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        try {
          localPath = await widget.coverCacheManager.ensureCached(
            subjectId: widget.subjectId,
            imageUrl: coverUrl,
            fetch: (String url) => widget.service.fetchImageWithRetry(url),
          ).timeout(const Duration(seconds: 12));
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _data = data;
        _localCoverPath = localPath;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    if (_loading) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在加载条目信息…', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    if (_error != null || _data == null) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.error_outline, size: 48, color: colors.error),
                const SizedBox(height: 12),
                Text(
                  _error ?? '未知错误',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.error),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () {
                    _loadData();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Map<String, dynamic> data = _data!;
    final String nameCn = readJsonStringNullable(data['name_cn']) ?? widget.item.nameCn;
    final String nameOrigin = readJsonStringNullable(data['name']) ?? widget.item.nameOrigin;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ListView(
            controller: scrollController,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildHeader(colors, nameCn, nameOrigin),
                        const SizedBox(height: 16),
                        _buildInfoChips(colors, data),
                        const SizedBox(height: 12),
                        if (data['meta_tags'] is List)
                          _buildGenreTags(colors, data['meta_tags'] as List<dynamic>),
                        if (data['infobox'] is List) ...[
                          const SizedBox(height: 12),
                          _buildInfobox(colors, data['infobox'] as List<dynamic>),
                        ],
                        const SizedBox(height: 12),
                        _buildFollowButton(colors),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildCover(colors),
                        if (data['rating'] is Map<String, dynamic>) ...[
                          const SizedBox(height: 12),
                          _buildRatingSection(colors, data['rating'] as Map<String, dynamic>),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (readJsonStringNullable(data['summary']) case final String summary?)
                _buildSummary(colors, summary),
              const SizedBox(height: 20),
              _buildActionButton(colors),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFollowButton(ColorScheme colors) {
    final bool followed = widget.isFollowed;
    return SizedBox(
      width: double.infinity,
      child: followed
          ? OutlinedButton.icon(
              onPressed: () { widget.onToggleFollow(); },
              icon: const Icon(Icons.star, size: 16),
              label: const Text('已关注'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
              ),
            )
          : FilledButton.tonalIcon(
              onPressed: () { widget.onToggleFollow(); },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('关注'),
            ),
    );
  }

  Widget _buildHeader(ColorScheme colors, String nameCn, String nameOrigin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              nameCn.isNotEmpty ? nameCn : nameOrigin,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (nameCn.isNotEmpty && nameOrigin.isNotEmpty && nameOrigin != nameCn) ...[
              const SizedBox(height: 4),
              Text(
                nameOrigin,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCover(ColorScheme colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: _localCoverPath != null && File(_localCoverPath!).existsSync()
          ? Image.file(
              File(_localCoverPath!),
              width: 260,
              height: 346,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _buildCoverPlaceholder(colors),
            )
          : _buildCoverPlaceholder(colors),
    );
  }

  Widget _buildCoverPlaceholder(ColorScheme colors) {
    return Container(
      width: 260,
      height: 346,
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.movie_creation_outlined,
        size: 36,
        color: colors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildRatingSection(ColorScheme colors, Map<String, dynamic> rating) {
    final double score = readJsonDouble(rating['score']) ?? 0;
    final int total = readJsonInt(rating['total']) ?? 0;
    final int rank = readJsonInt(rating['rank']) ?? 0;

    final dynamic rawCount = rating['count'];
    final List<int> values = List<int>.generate(10, (int i) {
      if (rawCount is Map) {
        return readJsonInt(rawCount['${i + 1}']) ?? 0;
      }
      return 0;
    });
    final int maxCount = values.fold<int>(0, (int a, int b) => a > b ? a : b);

    final _RatingChartLayout chartLayout = _RatingChartLayout(
      width: 250,
      height: 65,
      headerHeight: 13,
      headerBottomGap: 2,
      barGap: 2,
      minBarHeight: 2,
      contentPaddingHorizontal: 8,
      contentPaddingVertical: 5,
    );

    return Container(
      width: double.infinity,
      height: chartLayout.height,
      padding: EdgeInsets.symmetric(
        horizontal: chartLayout.contentPaddingHorizontal,
        vertical: chartLayout.contentPaddingVertical,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: chartLayout.headerHeight,
            child: Row(
              children: <Widget>[
                Text('评分分布', style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                Text(
                  '评分 $score | 共 $total 人${rank > 0 ? ' | #$rank' : ''}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: chartLayout.headerBottomGap),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double availableWidth = constraints.maxWidth;
                const double barCount = 10;
                final double effectiveGap = chartLayout.barGap;
                final double totalGap = effectiveGap * (barCount - 1);
                final double barWidth = ((availableWidth - totalGap) / barCount).clamp(2.0, double.infinity);
                const double labelHeight = 12;
                final List<int> reversed = List<int>.from(values.reversed);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: CustomPaint(
                        size: Size(availableWidth, (constraints.maxHeight - labelHeight).clamp(0, double.infinity)),
                        painter: _RatingBarPainter(
                          values: reversed,
                          maxCount: maxCount > 0 ? maxCount : 1,
                          barWidth: barWidth,
                          chartBarsHeight: (constraints.maxHeight - labelHeight - 2).clamp(0, double.infinity),
                          effectiveGap: effectiveGap,
                          minBarHeight: chartLayout.minBarHeight,
                          baseColor: colors.primary,
                        ),
                      ),
                    ),
                    Row(
                      children: List<Widget>.generate(10, (int i) {
                        return Expanded(
                          child: Text(
                            '${10 - i}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChips(ColorScheme colors, Map<String, dynamic> data) {
    final List<Widget> chips = <Widget>[];

    final String? date = readJsonStringNullable(data['date']);
    if (date != null && date.isNotEmpty) chips.add(_buildChip(colors, date));

    final String? platform = readJsonStringNullable(data['platform']);
    if (platform != null && platform.isNotEmpty) chips.add(_buildChip(colors, platform));

    final int? totalEps = readJsonInt(data['total_episodes']) ?? readJsonInt(data['eps']);
    if (totalEps != null && totalEps > 0) chips.add(_buildChip(colors, '共 $totalEps 话'));

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 4, children: chips),
    );
  }

  Widget _buildChip(ColorScheme colors, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: colors.onSecondaryContainer)),
    );
  }

  Widget _buildGenreTags(ColorScheme colors, List<dynamic> tags) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 6, runSpacing: 4,
        children: tags.whereType<String>().map((String tag) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(tag, style: TextStyle(fontSize: 11, color: colors.onTertiaryContainer)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInfobox(ColorScheme colors, List<dynamic> infobox) {
    if (infobox.isEmpty) return const SizedBox.shrink();
    final List<MapEntry<String, String>> entries = <MapEntry<String, String>>[];
    for (final dynamic entry in infobox) {
      if (entry is Map) {
        final String key = readJsonStringNullable(entry['key']) ?? '';
        final dynamic rawValue = entry['value'];
        String value;
        if (rawValue is List) {
          value = rawValue.whereType<String>().join('、');
        } else {
          value = readJsonStringNullable(rawValue) ?? '';
        }
        if (key.isNotEmpty && value.isNotEmpty) entries.add(MapEntry<String, String>(key, value));
      }
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries.take(6).map((MapEntry<String, String> e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 80,
                  child: Text('${e.key}:', style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600, color: colors.onSurfaceVariant,
                  )),
                ),
                Expanded(child: Text(e.value, style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummary(ColorScheme colors, String summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('简介', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            SizedBox(
              width: 20, height: 20,
              child: IconButton(
                padding: EdgeInsets.zero, iconSize: 14,
                icon: const Icon(Icons.copy),
                tooltip: '复制简介',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: summary));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('简介已复制'), duration: Duration(seconds: 2)),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedCrossFade(
          firstChild: Text(summary, maxLines: 4, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall),
          secondChild: Text(summary, style: Theme.of(context).textTheme.bodySmall),
          crossFadeState: _summaryExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        if (summary.length > 120)
          TextButton(
            onPressed: () => setState(() => _summaryExpanded = !_summaryExpanded),
            child: Text(_summaryExpanded ? '收起' : '展开'),
          ),
      ],
    );
  }

  Widget _buildActionButton(ColorScheme colors) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () { Navigator.of(context).pop(); widget.onOpenInBrowser(); },
        icon: const Icon(Icons.open_in_browser),
        label: const Text('在浏览器中打开 Bangumi 条目'),
      ),
    );
  }
}

class _RatingChartLayout {
  const _RatingChartLayout({
    required this.width,
    required this.height,
    required this.headerHeight,
    required this.headerBottomGap,
    required this.barGap,
    required this.minBarHeight,
    required this.contentPaddingHorizontal,
    required this.contentPaddingVertical,
  });

  final double width;
  final double height;
  final double headerHeight;
  final double headerBottomGap;
  final double barGap;
  final double minBarHeight;
  final double contentPaddingHorizontal;
  final double contentPaddingVertical;
}

/// 评分分布柱状图 CustomPainter
class _RatingBarPainter extends CustomPainter {
  _RatingBarPainter({
    required this.values,
    required this.maxCount,
    required this.barWidth,
    required this.chartBarsHeight,
    required this.effectiveGap,
    required this.minBarHeight,
    required this.baseColor,
  });

  final List<int> values;
  final int maxCount;
  final double barWidth;
  final double chartBarsHeight;
  final double effectiveGap;
  final double minBarHeight;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || maxCount <= 0) return;
    final Paint paint = Paint()..style = PaintingStyle.fill;
    final double startX = (size.width - _totalWidth) / 2;
    for (int i = 0; i < values.length; i++) {
      final double ratio = values[i] <= 0 ? 0.08 : values[i] / maxCount;
      final double barHeight = (chartBarsHeight * ratio).clamp(minBarHeight, chartBarsHeight);
      final Color color = Color.lerp(
        baseColor.withValues(alpha: 0.25), baseColor, ratio.clamp(0.0, 1.0),
      ) ?? baseColor;
      paint.color = color;
      final double x = startX + i * (barWidth + effectiveGap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, chartBarsHeight - barHeight, barWidth, barHeight), const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RatingBarPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.maxCount != maxCount ||
        oldDelegate.barWidth != barWidth ||
        oldDelegate.chartBarsHeight != chartBarsHeight ||
        oldDelegate.effectiveGap != effectiveGap ||
        oldDelegate.minBarHeight != minBarHeight ||
        oldDelegate.baseColor != baseColor;
  }

  double get _totalWidth => values.length * barWidth + (values.length - 1) * effectiveGap;
}
