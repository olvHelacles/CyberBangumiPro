import 'dart:io';

import 'package:flutter/material.dart';

import '../models/subject_item.dart';
import '../services/bangumi_service.dart';
import '../stores/cover_cache_manager.dart';
import '../widgets/subject_tile.dart';

/// Search tab for searching Bangumi subjects with lazy pagination.
class SearchTab extends StatefulWidget {
  const SearchTab({
    super.key,
    required this.service,
    required this.coverCacheManager,
    required this.watchIds,
    required this.coverCacheConcurrency,
    required this.onToggleFollow,
    required this.onShowDetail,
  });

  final BangumiService service;
  final CoverCacheManager coverCacheManager;
  final Set<String> watchIds;
  final int coverCacheConcurrency;
  final ValueChanged<SubjectItem> onToggleFollow;
  final ValueChanged<SubjectItem> onShowDetail;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  static const int _pageSize = 10;

  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _searchCoverPaths = <String, String>{};
  List<SearchSubjectResult> _allSearchResults = <SearchSubjectResult>[];
  int _searchTotalResults = 0;
  int _currentSearchPage = 0;
  bool _isSearching = false;
  String _searchError = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchError = '';
      _allSearchResults = <SearchSubjectResult>[];
      _searchTotalResults = 0;
      _currentSearchPage = 0;
    });

    try {
      final SearchSubjectsResponse response = await widget.service.searchSubjects(
        keyword,
        limit: _pageSize,
        offset: 0,
      );

      if (!mounted) return;

      // Sort by popularity desc, then rating score desc.
      final List<SearchSubjectResult> sorted = List<SearchSubjectResult>.from(
        response.results,
      );
      sorted.sort((SearchSubjectResult a, SearchSubjectResult b) {
        final int popCmp = b.popularity.compareTo(a.popularity);
        if (popCmp != 0) return popCmp;
        final double aScore = a.ratingScore ?? 0;
        final double bScore = b.ratingScore ?? 0;
        return bScore.compareTo(aScore);
      });

      setState(() {
        _allSearchResults = sorted;
        _searchTotalResults = response.total;
        _isSearching = false;
      });

      _cacheSearchResultCovers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = '搜索失败：$e';
      });
    }
  }

  Future<void> _navigateSearchPage(int page) async {
    final String keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = '';
    });

    try {
      final int offset = page * _pageSize;
      final SearchSubjectsResponse response = await widget.service.searchSubjects(
        keyword,
        limit: _pageSize,
        offset: offset,
      );

      if (!mounted) return;

      // Sort by popularity desc, then rating score desc.
      final List<SearchSubjectResult> sorted = List<SearchSubjectResult>.from(
        response.results,
      );
      sorted.sort((SearchSubjectResult a, SearchSubjectResult b) {
        final int popCmp = b.popularity.compareTo(a.popularity);
        if (popCmp != 0) return popCmp;
        final double aScore = a.ratingScore ?? 0;
        final double bScore = b.ratingScore ?? 0;
        return bScore.compareTo(aScore);
      });

      setState(() {
        _allSearchResults = sorted;
        _currentSearchPage = page;
        _isSearching = false;
      });

      _cacheSearchResultCovers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = '翻页失败：$e';
      });
    }
  }

  Future<void> _cacheSearchResultCovers() async {
    final int maxWorkers = widget.coverCacheConcurrency;
    int nextIndex = 0;

    int? takeNextIndex() {
      if (nextIndex >= _allSearchResults.length) return null;
      final int current = nextIndex;
      nextIndex += 1;
      return current;
    }

    Future<void> processOne(int i) async {
      final SearchSubjectResult r = _allSearchResults[i];
      final String id = r.subject.subjectId;
      if (id.isEmpty || r.subject.coverUrl.isEmpty) return;
      if (_searchCoverPaths.containsKey(id)) return;
      try {
        final String? path = await widget.coverCacheManager.ensureCached(
          subjectId: id,
          imageUrl: r.subject.coverUrl,
          fetch: (String url) => widget.service.fetchImageWithRetry(
            url,
            purpose: '搜索结果封面缓存',
          ),
        ).timeout(const Duration(seconds: 12));
        if (path != null && mounted) {
          setState(() {
            _searchCoverPaths[id] = path;
          });
        }
      } catch (_) {}
    }

    Future<void> worker() async {
      while (true) {
        final int? i = takeNextIndex();
        if (i == null) return;
        await processOne(i);
      }
    }

    final int workerCount =
        _allSearchResults.length < maxWorkers
            ? _allSearchResults.length
            : maxWorkers;
    if (workerCount <= 0) return;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
  }

  Widget _buildSearchResultCover(SubjectItem item) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String? cached = _searchCoverPaths[item.subjectId];
    if (cached != null && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        width: 72,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            buildCoverPlaceholder(width: 72, height: 96, colors: colors),
      );
    }
    return buildCoverPlaceholder(width: 72, height: 96, colors: colors);
  }

  Widget _buildBadge(String text, {bool isHighRating = false}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isHighRating
            ? colors.tertiaryContainer
            : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: isHighRating
              ? colors.onTertiaryContainer
              : colors.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildSearchResultTile(SearchSubjectResult result) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final SubjectItem item = result.subject;
    final bool isFollowed =
        widget.watchIds.any((String id) => id == item.subjectId);
    final String title =
        item.displayName.isNotEmpty ? item.displayName : item.subjectId;
    final String subtitle = item.nameOrigin.isNotEmpty &&
            item.nameOrigin != item.displayName
        ? item.nameOrigin
        : '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Cover image (72x96)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => widget.onShowDetail(item),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.coverUrl.isNotEmpty
                    ? _buildSearchResultCover(item)
                    : buildCoverPlaceholder(
                        width: 72, height: 96, colors: colors),
              ),
            ),
            const SizedBox(width: 12),
            // Title + badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  GestureDetector(
                    onTap: () => widget.onShowDetail(item),
                    child: Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      if (result.ratingScore != null &&
                          result.ratingScore! > 0)
                        _buildBadge(
                          '评分 ${result.ratingScore!.toStringAsFixed(1)}',
                          isHighRating: result.ratingScore! >= 7.5,
                        ),
                      if (result.airDate.isNotEmpty)
                        _buildBadge(result.airDate),
                    ],
                  ),
                ],
              ),
            ),
            // Follow/unfollow button
            const SizedBox(width: 4),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  icon: Icon(
                    isFollowed ? Icons.star : Icons.star_border,
                    color: isFollowed ? Colors.amber : null,
                  ),
                  tooltip: isFollowed ? '取消关注' : '关注',
                  onPressed: () => widget.onToggleFollow(item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int totalPages = _searchTotalResults == 0
        ? 0
        : (_searchTotalResults + _pageSize - 1) ~/ _pageSize;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: '搜索番剧',
              hintText: '输入番剧日文名或中文名',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () =>
                    _performSearch(_searchController.text.trim()),
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              if (value.trim().isEmpty) {
                setState(() {
                  _allSearchResults = <SearchSubjectResult>[];
                  _searchTotalResults = 0;
                  _searchError = '';
                  _currentSearchPage = 0;
                });
              }
            },
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) _performSearch(value.trim());
            },
          ),
        ),
        if (!_isSearching &&
            _searchError.isEmpty &&
            _allSearchResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 $_searchTotalResults 条结果（按热度排序）',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant),
              ),
            ),
          ),
        if (_searchError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _searchError,
              style:
                  TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_isSearching)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_isSearching && _searchError.isEmpty)
          Expanded(
            child: _allSearchResults.isEmpty
                ? const Center(child: Text('输入关键词搜索番剧'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _allSearchResults.length + 1,
                    itemBuilder: (BuildContext context, int index) {
                      if (index < _allSearchResults.length) {
                        return _buildSearchResultTile(
                            _allSearchResults[index]);
                      }
                      // Pagination footer
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            FilledButton.tonal(
                              onPressed: _currentSearchPage > 0
                                  ? () => _navigateSearchPage(
                                      _currentSearchPage - 1)
                                  : null,
                              child: const Text('上一页'),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              '${_currentSearchPage + 1} / $totalPages 页',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium,
                            ),
                            const SizedBox(width: 16),
                            FilledButton.tonal(
                              onPressed:
                                  _currentSearchPage + 1 < totalPages
                                      ? () => _navigateSearchPage(
                                          _currentSearchPage + 1)
                                      : null,
                              child: const Text('下一页'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}
