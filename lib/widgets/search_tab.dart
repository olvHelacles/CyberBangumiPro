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

  // Filter state.
  int? _filterYearFrom;
  int? _filterYearTo;
  double? _filterMinRating;
  int? _filterMinRatingCount;
  List<String> _filterTags = <String>[];
  String? _filterRegion;
  String? _filterCategory;

  bool _browseMode = false;
  String _sortBy = 'heat';

  String get _sortLabel {
    switch (_sortBy) {
      case 'score':
        return '评分';
      case 'heat':
      default:
        return '收藏数';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SearchSubjectResult> _sortResults(
    List<SearchSubjectResult> results,
    String keyword,
  ) {
    final String kw = keyword.trim().toLowerCase();
    final String kwNorm = kw.replaceAll(RegExp(r'[\s\-_:：;；・]'), '');

    int matchScore(SearchSubjectResult r) {
      final String cn = r.subject.nameCn.toLowerCase();
      final String jp = r.subject.nameOrigin.toLowerCase();
      final String cnNorm = cn.replaceAll(RegExp(r'[\s\-_:：;；・]'), '');
      final String jpNorm = jp.replaceAll(RegExp(r'[\s\-_:：;；・]'), '');

      if (cn == kw || jp == kw) return 10000;
      if (cn.contains(kw)) return 8000 + (kw.length * 1000 ~/ cn.length);
      if (jp.contains(kw)) return 7000 + (kw.length * 1000 ~/ jp.length);
      if (cnNorm == kwNorm || jpNorm == kwNorm) return 6000;
      if (cnNorm.contains(kwNorm)) {
        return 4000 + (kwNorm.length * 1000 ~/ cnNorm.length);
      }
      if (jpNorm.contains(kwNorm)) {
        return 3000 + (kwNorm.length * 1000 ~/ jpNorm.length);
      }
      return 0;
    }

    final List<SearchSubjectResult> sorted =
        List<SearchSubjectResult>.from(results);
    sorted.sort((SearchSubjectResult a, SearchSubjectResult b) {
      final int msA = matchScore(a);
      final int msB = matchScore(b);
      final int diff = msB - msA;
      if (diff.abs() <= 2000) {
        final int popCmp = b.popularity.compareTo(a.popularity);
        if (popCmp != 0) return popCmp;
      } else {
        if (diff != 0) return diff;
      }
      final double aScore = a.ratingScore ?? 0;
      final double bScore = b.ratingScore ?? 0;
      return bScore.compareTo(aScore);
    });
    return sorted;
  }

  bool get _hasActiveFilters =>
      _filterYearFrom != null ||
      _filterYearTo != null ||
      _filterMinRating != null ||
      _filterMinRatingCount != null ||
      _filterTags.isNotEmpty ||
      _filterRegion != null ||
      _filterCategory != null;

  List<String>? _buildMetaTags() {
    final List<String> tags = <String>[
      ..._filterTags,
      if (_filterRegion != null) _filterRegion!,
      if (_filterCategory != null) _filterCategory!,
    ];
    return tags.isNotEmpty ? tags : null;
  }

  Future<void> _clearFilters() async {
    setState(() {
      _filterYearFrom = null;
      _filterYearTo = null;
      _filterMinRating = null;
      _filterMinRatingCount = null;
      _filterTags = <String>[];
      _filterRegion = null;
      _filterCategory = null;
    });
    await _triggerSearch();
  }

  Future<void> _triggerSearch() async {
    final String kw = _searchController.text.trim();
    if (_browseMode || kw.isNotEmpty || _hasActiveFilters) {
      await _performSearch(kw);
    }
  }

  String _buildYearLabel() {
    if (_filterYearFrom != null && _filterYearTo != null) {
      return '${_filterYearFrom}-$_filterYearTo';
    }
    if (_filterYearFrom != null) return '$_filterYearFrom年起';
    if (_filterYearTo != null) return '$_filterYearTo年前';
    return '年份不限';
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Future<void> _showYearRangePicker() async {
    final List<int> years = <int>[
      for (int y = 2026; y >= 2000; y--) y,
    ];
    final List<int?>? result = await showDialog<List<int?>>(
      context: context,
      builder: (BuildContext context) {
        int? from = _filterYearFrom;
        int? to = _filterYearTo;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('播出年份范围'),
              content: SizedBox(
                width: 300,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: from,
                        decoration: const InputDecoration(
                          labelText: '从',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: <DropdownMenuItem<int?>>[
                          const DropdownMenuItem<int?>(
                            value: null, child: Text('不限'),
                          ),
                          for (final int y in years)
                            DropdownMenuItem<int?>(
                              value: y, child: Text('$y年'),
                            ),
                        ],
                        onChanged: (int? v) =>
                            setLocalState(() => from = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: to,
                        decoration: const InputDecoration(
                          labelText: '到',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: <DropdownMenuItem<int?>>[
                          const DropdownMenuItem<int?>(
                            value: null, child: Text('不限'),
                          ),
                          for (final int y in years)
                            DropdownMenuItem<int?>(
                              value: y, child: Text('$y年'),
                            ),
                        ],
                        onChanged: (int? v) =>
                            setLocalState(() => to = v),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(<int?>[from, to]),
                  child: const Text('应用'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    setState(() {
      _filterYearFrom = result[0];
      _filterYearTo = result[1];
    });
    await _triggerSearch();
  }

  Future<void> _showRatingPicker() async {
    const List<double?> ratingOptions = <double?>[
      null, 6, 7, 8, 9,
    ];
    const List<String> ratingLabels = <String>[
      '不限', '≥ 6', '≥ 7', '≥ 8', '≥ 9',
    ];
    const List<int?> countOptions = <int?>[
      null, 100, 500, 1000, 5000, 10000,
    ];
    const List<String> countLabels = <String>[
      '不限', '≥ 100', '≥ 500', '≥ 1000', '≥ 5000', '≥ 10000',
    ];

    double? pickRating = _filterMinRating;
    int? pickCount = _filterMinRatingCount;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        int ratingIndex = ratingOptions.indexOf(_filterMinRating);
        if (ratingIndex < 0) ratingIndex = 0;
        int countIndex = countOptions.indexOf(_filterMinRatingCount);
        if (countIndex < 0) countIndex = 0;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('评分 & 评分人数'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('最低评分',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: List<Widget>.generate(
                        ratingOptions.length, (int i) {
                      final bool selected = ratingIndex == i;
                      return ChoiceChip(
                        label: Text(ratingLabels[i],
                            style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        onSelected: (_) =>
                            setLocalState(() => ratingIndex = i),
                        visualDensity: VisualDensity.compact,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 6),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  const Text('评分人数',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: List<Widget>.generate(
                        countOptions.length, (int i) {
                      final bool selected = countIndex == i;
                      return ChoiceChip(
                        label: Text(countLabels[i],
                            style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        onSelected: (_) =>
                            setLocalState(() => countIndex = i),
                        visualDensity: VisualDensity.compact,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 6),
                      );
                    }),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    pickRating = ratingOptions[ratingIndex];
                    pickCount = countOptions[countIndex];
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('应用'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) return;
    if (pickRating == _filterMinRating && pickCount == _filterMinRatingCount) {
      return;
    }
    setState(() {
      _filterMinRating = pickRating;
      _filterMinRatingCount = pickCount;
    });
    await _triggerSearch();
  }

  Future<void> _showTagEditor() async {
    const List<String> commonTags = <String>[
      '科幻', '喜剧', '同人', '百合', '校园', '惊悚', '后宫', '机战',
      '悬疑', '恋爱', '奇幻', '推理', '运动', '耽美', '音乐', '战斗',
      '冒险', '萌系', '穿越', '玄幻', '乙女', '恐怖', '历史', '日常',
      '剧情', '武侠', '美食', '职场',
    ];
    final TextEditingController tagController = TextEditingController();
    final List<String> currentTags = List<String>.from(_filterTags);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('标签筛选'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: tagController,
                      decoration: InputDecoration(
                        labelText: '输入标签后按回车添加',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () {
                            final String t =
                                tagController.text.trim();
                            if (t.isNotEmpty &&
                                !currentTags.contains(t)) {
                              setLocalState(() {
                                currentTags.add(t);
                                tagController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      onSubmitted: (String value) {
                        final String t = value.trim();
                        if (t.isNotEmpty && !currentTags.contains(t)) {
                          setLocalState(() {
                            currentTags.add(t);
                            tagController.clear();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text('常用标签',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: commonTags.map((String tag) {
                        final bool selected =
                            currentTags.contains(tag);
                        return ChoiceChip(
                          label: Text(tag,
                              style: const TextStyle(fontSize: 11)),
                          selected: selected,
                          onSelected: (bool value) {
                            setLocalState(() {
                              if (value) {
                                currentTags.add(tag);
                              } else {
                                currentTags.remove(tag);
                              }
                            });
                          },
                          visualDensity: VisualDensity.compact,
                          labelPadding: const EdgeInsets.symmetric(
                              horizontal: 6),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(currentTags),
                  child: const Text('应用'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    setState(() => _filterTags = result);
    await _triggerSearch();
  }

  Future<void> _showRegionPicker() async {
    const List<String?> options = <String?>[
      null, '日本', '中国', '韩国', '美国', '英国', '法国', '其他',
    ];
    const List<String> labels = <String>[
      '不限', '日本', '中国', '韩国', '美国', '英国', '法国', '其他',
    ];
    int selectedIndex = options.indexOf(_filterRegion);
    if (selectedIndex < 0) selectedIndex = 0;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('地区'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(options.length, (int i) {
                  final bool selected = selectedIndex == i;
                  return ListTile(
                    title: Text(labels[i]),
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onTap: () =>
                        setLocalState(() => selectedIndex = i),
                    dense: true,
                  );
                }),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(options[selectedIndex]),
                  child: const Text('应用'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == _filterRegion) return;
    setState(() => _filterRegion = result);
    await _triggerSearch();
  }

  Future<void> _showCategoryPicker() async {
    const List<String?> options = <String?>[
      null, 'TV', 'WEB', 'OVA', '剧场版', '动态漫画', '其他',
    ];
    const List<String> labels = <String>[
      '不限', 'TV', 'WEB', 'OVA', '剧场版', '动态漫画', '其他',
    ];
    int selectedIndex = options.indexOf(_filterCategory);
    if (selectedIndex < 0) selectedIndex = 0;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('分类'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(options.length, (int i) {
                  final bool selected = selectedIndex == i;
                  return ListTile(
                    title: Text(labels[i]),
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onTap: () =>
                        setLocalState(() => selectedIndex = i),
                    dense: true,
                  );
                }),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(options[selectedIndex]),
                  child: const Text('应用'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == _filterCategory) return;
    setState(() => _filterCategory = result);
    await _triggerSearch();
  }

  Future<void> _showSortPicker() async {
    const List<String> options = <String>['heat', 'score'];
    const List<String> labels = <String>['收藏数', '评分'];
    int selectedIndex = options.indexOf(_sortBy);
    if (selectedIndex < 0) selectedIndex = 0;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('排序依据'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(options.length, (int i) {
                  final bool selected = selectedIndex == i;
                  return ListTile(
                    title: Text(labels[i]),
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onTap: () => setLocalState(() => selectedIndex = i),
                    dense: true,
                  );
                }),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(options[selectedIndex]),
                  child: const Text('应用'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || result == _sortBy) return;
    setState(() => _sortBy = result);
    await _triggerSearch();
  }

  Future<void> _performSearch(String keyword) async {
    final String kw = keyword.trim();
    final bool useWildcard = _browseMode || (kw.isEmpty && _hasActiveFilters);
    if (kw.isEmpty && !useWildcard) return;
    setState(() {
      _isSearching = true;
      _searchError = '';
      _allSearchResults = <SearchSubjectResult>[];
      _searchTotalResults = 0;
      _currentSearchPage = 0;
    });

    try {
      final SearchSubjectsResponse response = await widget.service.searchSubjects(
        useWildcard ? '*' : keyword,
        sort: _sortBy,
        limit: _pageSize,
        offset: 0,
        airDateYearFrom: _filterYearFrom,
        airDateYearTo: _filterYearTo,
        minRating: _filterMinRating,
        minRatingCount: _filterMinRatingCount,
        tags: _buildMetaTags(),
      );

      if (!mounted) return;

      final List<SearchSubjectResult> sorted =
          _sortResults(response.results, keyword);

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
    final bool useWildcard = _browseMode || (keyword.isEmpty && _hasActiveFilters);
    if (keyword.isEmpty && !useWildcard) return;

    setState(() {
      _isSearching = true;
      _searchError = '';
    });

    try {
      final int offset = page * _pageSize;
      final SearchSubjectsResponse response = await widget.service.searchSubjects(
        useWildcard ? '*' : keyword,
        sort: _sortBy,
        limit: _pageSize,
        offset: offset,
        airDateYearFrom: _filterYearFrom,
        airDateYearTo: _filterYearTo,
        minRating: _filterMinRating,
        minRatingCount: _filterMinRatingCount,
        tags: _buildMetaTags(),
      );

      if (!mounted) return;

      final List<SearchSubjectResult> sorted =
          _sortResults(response.results, keyword);

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
        // Browse mode toggle
        if (!_browseMode)
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
              if (value.trim().isEmpty && !_hasActiveFilters) {
                setState(() {
                  _allSearchResults = <SearchSubjectResult>[];
                  _searchTotalResults = 0;
                  _searchError = '';
                  _currentSearchPage = 0;
                });
              }
            },
            onSubmitted: (value) {
              final String kw = value.trim();
              if (kw.isNotEmpty || _hasActiveFilters) _performSearch(kw);
            },
          ),
        ),
        // Filter bar + sort + mode toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      _filterChip(
                        icon: Icons.category,
                        label: _filterCategory ?? '分类不限',
                        onTap: _showCategoryPicker,
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        icon: Icons.language,
                        label: _filterRegion ?? '地区不限',
                        onTap: _showRegionPicker,
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        icon: Icons.calendar_today,
                        label: _buildYearLabel(),
                        onTap: _showYearRangePicker,
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        icon: Icons.star,
                        label: _filterMinRating != null
                            ? '≥ $_filterMinRating${_filterMinRatingCount != null ? ", ≥$_filterMinRatingCount人" : ""}'
                            : _filterMinRatingCount != null
                                ? '≥$_filterMinRatingCount人'
                                : '评分不限',
                        onTap: _showRatingPicker,
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        icon: Icons.label,
                        label: _filterTags.isEmpty
                            ? '标签不限'
                            : _filterTags.join(', '),
                        onTap: _showTagEditor,
                      ),
                      if (_hasActiveFilters) ...[
                        const SizedBox(width: 4),
                        TextButton.icon(
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('清除', style: TextStyle(fontSize: 12)),
                          onPressed: _clearFilters,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_browseMode) ...[
                ActionChip(
                  avatar: const Icon(Icons.sort, size: 14),
                  label: Text(_sortLabel,
                      style: const TextStyle(fontSize: 12)),
                  onPressed: _showSortPicker,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                const SizedBox(width: 4),
              ],
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: true, label: Text('浏览', style: TextStyle(fontSize: 11))),
                  ButtonSegment<bool>(value: false, label: Text('搜索', style: TextStyle(fontSize: 11))),
                ],
                selected: <bool>{_browseMode},
                onSelectionChanged: (Set<bool> selected) {
                  final bool v = selected.first;
                  setState(() {
                    _browseMode = v;
                    if (v) {
                      _filterCategory ??= 'TV';
                      _filterRegion ??= '日本';
                      _filterMinRatingCount ??= 100;
                    }
                  });
                  if (v) _performSearch('');
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 6)),
                ),
              ),
            ],
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
