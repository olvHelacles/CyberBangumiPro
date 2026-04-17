import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

const String calendarUrl = 'https://bangumi.tv/calendar';
const String bangumiApiBaseUrl = 'https://api.bgm.tv';
const String bgmListOnAirApiUrl = 'https://bgmlist.com/api/v1/bangumi/onair';
const String watchlistStorageKey = 'watchlist';
const String calendarAutoRefreshMonthKey = 'calendar_auto_refresh_month';
const String calendarCacheTimezoneTokenKey = 'calendar_cache_timezone_token_v1';
const String settingsStorageKey = 'app_settings_v1';
const String themeModeSettingKey = 'theme_mode_v1';
const String appBarBackgroundImageEnabledSettingKey =
  'appbar_background_image_enabled';
const String appBarBackgroundImagePathSettingKey =
  'appbar_background_image_path';
const String progressCorrectionStorageKey = 'progress_corrections_v1';
const String progressCorrectionDeltaStorageKey =
  'progress_correction_deltas_v1';
const String timezoneConversionEnabledSettingKey =
    'timezone_conversion_enabled';
const String timezoneOffsetMinutesSettingKey = 'timezone_offset_minutes';
const String appUserAgent = 'OlvSilence/my-private-project';
const String browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const Map<int, String> weekdayMap = <int, String>{
  1: '星期一',
  2: '星期二',
  3: '星期三',
  4: '星期四',
  5: '星期五',
  6: '星期六',
  7: '星期日',
};

const Map<String, String> requestHeaders = <String, String>{
  'User-Agent': browserUserAgent,
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
};

const Map<String, String> imageRequestHeaders = <String, String>{
  'Referer': 'https://bangumi.tv/',
  'User-Agent': browserUserAgent,
};

const List<String> sansFallbacks = <String>[
  'Microsoft YaHei',
  'Microsoft YaHei UI',
  'PingFang SC',
  'Noto Sans CJK SC',
  'Noto Sans SC',
];

const int defaultSettingProgressConcurrency = 10;
const int defaultSettingCoverCacheConcurrency = 12;
const bool defaultSettingTimezoneConversionEnabled = true;
const int defaultSettingTimezoneOffsetMinutes = 8 * 60;

/// BroadcastScheduleHint：组件或数据结构定义。
class BroadcastScheduleHint {
  const BroadcastScheduleHint({required this.weekday, required this.time});

  final String weekday;
  final String time;
}

/// ConvertedWeekdayTime：组件或数据结构定义。
class ConvertedWeekdayTime {
  const ConvertedWeekdayTime({required this.weekday, required this.time});

  final String weekday;
  final String time;
}

/// BgmListOnAirEntry：组件或数据结构定义。
class BgmListOnAirEntry {
  const BgmListOnAirEntry({required this.timeJst, required this.jpTitles});

  final String timeJst;
  final List<String> jpTitles;
}

/// BgmListScheduleCandidate：BGMLIST 直接构建周历所需字段。
class BgmListScheduleCandidate {
  const BgmListScheduleCandidate({
    required this.subjectId,
    required this.subjectUrl,
    required this.titleJp,
    required this.titleCn,
    required this.coverUrl,
    required this.weekdayJst,
    required this.updateTimeJst,
    required this.beginJst,
    required this.periodDays,
  });

  final String subjectId;
  final String subjectUrl;
  final String titleJp;
  final String titleCn;
  final String coverUrl;
  final String weekdayJst;
  final String updateTimeJst;
  final DateTime beginJst;
  final int periodDays;
}

/// BroadcastTimeConverter：组件或数据结构定义。
class BroadcastTimeConverter {
  static const int jstOffsetMinutes = 9 * 60;
  static const int minTimezoneOffsetMinutes = -12 * 60;
  static const int maxTimezoneOffsetMinutes = 14 * 60;

  
  static int normalizeTimezoneOffsetMinutes(int value) {
    return value.clamp(minTimezoneOffsetMinutes, maxTimezoneOffsetMinutes);
  }

  
  static String formatUtcOffsetLabel(int offsetMinutes) {
    final int normalized = normalizeTimezoneOffsetMinutes(offsetMinutes);
    final String sign = normalized >= 0 ? '+' : '-';
    final int absMinutes = normalized.abs();
    final int hour = absMinutes ~/ 60;
    final int minute = absMinutes % 60;
    if (minute == 0) {
      return 'UTC$sign$hour';
    }
    return 'UTC$sign$hour:${minute.toString().padLeft(2, '0')}';
  }

  
  static int? weekdayToIndex(String weekdayText) {
    final String value = weekdayText.trim();
    if (value.isEmpty) {
      return null;
    }
    for (final MapEntry<int, String> entry in weekdayMap.entries) {
      if (entry.value == value) {
        return entry.key;
      }
    }
    return null;
  }

  
  static String weekdayFromIndex(int index) {
    final int wrapped = _wrapWeekday(index);
    return weekdayMap[wrapped] ?? '星期一';
  }

  
  static int _wrapWeekday(int value) {
    return _positiveMod(value - 1, 7) + 1;
  }

  
  static int _positiveMod(int value, int modulo) {
    final int result = value % modulo;
    return result < 0 ? result + modulo : result;
  }

  
  static int _floorDiv(int value, int divisor) {
    if (divisor == 0) {
      throw ArgumentError('divisor cannot be zero');
    }
    final int positiveDivisor = divisor < 0 ? -divisor : divisor;
    if (value >= 0) {
      return value ~/ positiveDivisor;
    }
    return -(((-value) + positiveDivisor - 1) ~/ positiveDivisor);
  }

  
  static int? parseClockMinutes(String timeText, {int maxHour = 47}) {
    final RegExpMatch? match = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(timeText.trim());
    if (match == null) {
      return null;
    }
    final int? hour = int.tryParse(match.group(1) ?? '');
    final int? minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > maxHour || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  
  static String formatClockMinutes(int minutes) {
    final int normalized = _positiveMod(minutes, 24 * 60);
    final int hour = normalized ~/ 60;
    final int minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static ConvertedWeekdayTime? convertWeekdayAndTime({
    required String weekday,
    required String time,
    required int fromOffsetMinutes,
    required int toOffsetMinutes,
  }) {
    final int? weekdayIndex = weekdayToIndex(weekday);
    final int? sourceMinutes = parseClockMinutes(time);
    if (weekdayIndex == null || sourceMinutes == null) {
      return null;
    }

    final int normalizedFrom = normalizeTimezoneOffsetMinutes(
      fromOffsetMinutes,
    );
    final int normalizedTo = normalizeTimezoneOffsetMinutes(toOffsetMinutes);

    final int sourceDayCarry = sourceMinutes ~/ (24 * 60);
    final int sourceMinuteInDay = _positiveMod(sourceMinutes, 24 * 60);
    final int sourceWeekday = _wrapWeekday(weekdayIndex + sourceDayCarry);
    final int delta = normalizedTo - normalizedFrom;

    final int targetAbsolute = sourceMinuteInDay + delta;
    final int targetDayCarry = _floorDiv(targetAbsolute, 24 * 60);
    final int targetMinuteInDay = _positiveMod(targetAbsolute, 24 * 60);
    final int targetWeekday = _wrapWeekday(sourceWeekday + targetDayCarry);

    return ConvertedWeekdayTime(
      weekday: weekdayFromIndex(targetWeekday),
      time: formatClockMinutes(targetMinuteInDay),
    );
  }

  static DateTime? resolveEpisodeBroadcastInDisplayTime({
    required DateTime airdateJst,
    required String displayTime,
    required int displayOffsetMinutes,
    String displayWeekday = '',
  }) {
    final int? displayMinutesRaw = parseClockMinutes(displayTime);
    if (displayMinutesRaw == null) {
      return null;
    }

    final int normalizedDisplayOffset = normalizeTimezoneOffsetMinutes(
      displayOffsetMinutes,
    );
    final int displayDayCarry = displayMinutesRaw ~/ (24 * 60);
    final int displayMinuteInDay = _positiveMod(displayMinutesRaw, 24 * 60);

    final int jstAbsolute =
        displayMinuteInDay + (jstOffsetMinutes - normalizedDisplayOffset);
    final int jstDayCarry = displayDayCarry + _floorDiv(jstAbsolute, 24 * 60);
    final int jstMinuteInDay = _positiveMod(jstAbsolute, 24 * 60);

    // Use UTC baseline to avoid mixing local and UTC DateTime semantics.
    final DateTime jstDate = DateTime.utc(
      airdateJst.year,
      airdateJst.month,
      airdateJst.day,
    ).add(Duration(days: jstDayCarry));
    final DateTime jstMomentUtc = jstDate.add(
      Duration(minutes: jstMinuteInDay - jstOffsetMinutes),
    );
    DateTime displayMoment = jstMomentUtc.add(
      Duration(minutes: normalizedDisplayOffset),
    );

    final int? expectedWeekday = weekdayToIndex(displayWeekday);
    if (expectedWeekday == null) {
      return displayMoment;
    }

    final int forward = (expectedWeekday - displayMoment.weekday + 7) % 7;
    final int backward = forward - 7;
    final int shiftDays =
        forward.abs() <= backward.abs() ? forward : backward;
    displayMoment = displayMoment.add(Duration(days: shiftDays));
    return displayMoment;
  }
}


TextStyle _styleWithWeight(TextStyle? base, FontWeight weight) {
  return (base ?? const TextStyle()).copyWith(
    fontFamilyFallback: sansFallbacks,
    fontWeight: weight,
    height: 1.28,
  );
}

/// _BottomEdgeOnlyClipper：组件或数据结构定义。
class _BottomEdgeOnlyClipper extends CustomClipper<Rect> {
  const _BottomEdgeOnlyClipper();

  static const double _topAllowance = 4096;

  @override
  
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, -_topAllowance, size.width, size.height);
  }

  @override
  
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) {
    return false;
  }
}


TextTheme buildUnifiedTextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: _styleWithWeight(base.displayLarge, FontWeight.w600),
    displayMedium: _styleWithWeight(base.displayMedium, FontWeight.w600),
    displaySmall: _styleWithWeight(base.displaySmall, FontWeight.w600),
    headlineLarge: _styleWithWeight(base.headlineLarge, FontWeight.w600),
    headlineMedium: _styleWithWeight(base.headlineMedium, FontWeight.w600),
    headlineSmall: _styleWithWeight(base.headlineSmall, FontWeight.w600),
    titleLarge: _styleWithWeight(base.titleLarge, FontWeight.w600),
    titleMedium: _styleWithWeight(base.titleMedium, FontWeight.w500),
    titleSmall: _styleWithWeight(base.titleSmall, FontWeight.w500),
    bodyLarge: _styleWithWeight(base.bodyLarge, FontWeight.w400),
    bodyMedium: _styleWithWeight(base.bodyMedium, FontWeight.w400),
    bodySmall: _styleWithWeight(base.bodySmall, FontWeight.w400),
    labelLarge: _styleWithWeight(base.labelLarge, FontWeight.w500),
    labelMedium: _styleWithWeight(base.labelMedium, FontWeight.w500),
    labelSmall: _styleWithWeight(base.labelSmall, FontWeight.w400),
  );
}


ThemeMode themeModeFromStorageValue(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}


String themeModeToStorageValue(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}


String themeModeDisplayText(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return '跟随系统';
    case ThemeMode.light:
      return '亮色模式';
    case ThemeMode.dark:
      return '深色模式';
  }
}


ThemeData buildAppTheme(Brightness brightness) {
  final ThemeData base = ThemeData(useMaterial3: true, brightness: brightness);
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0A7B83),
    brightness: brightness,
  );
  final bool isDark = brightness == Brightness.dark;
  final Color appBarBackground = isDark
      ? colorScheme.surfaceContainerHigh
      : const Color(0xFFE85D9E);
  final Color appBarForeground = isDark ? colorScheme.onSurface : Colors.white;
  final TextTheme baseTextTheme = base.textTheme;

  return base.copyWith(
    colorScheme: colorScheme,
    textTheme: buildUnifiedTextTheme(base.textTheme),
    primaryTextTheme: buildUnifiedTextTheme(base.primaryTextTheme),
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: appBarBackground,
      foregroundColor: appBarForeground,
      iconTheme: IconThemeData(color: appBarForeground, weight: 300),
      actionsIconTheme: IconThemeData(color: appBarForeground, weight: 300),
      titleTextStyle: _styleWithWeight(
        baseTextTheme.titleLarge,
        FontWeight.w500,
      ).copyWith(
        fontSize: 20,
        fontFamily: '29LT Bukra',
        fontStyle: FontStyle.italic,
        color: appBarForeground,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: appBarForeground,
      unselectedLabelColor: appBarForeground.withValues(
        alpha: isDark ? 0.74 : 0.86,
      ),
      indicatorColor: appBarForeground,
      labelStyle: _styleWithWeight(baseTextTheme.titleMedium, FontWeight.w600),
      unselectedLabelStyle: _styleWithWeight(
        baseTextTheme.titleMedium,
        FontWeight.w500,
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const WindowOptions windowOptions = WindowOptions(
      center: true,
      title: 'CyberBangumi Pro',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      // ignore: invalid_use_of_visible_for_testing_member
      HardwareKeyboard.instance.clearState();
    });
  }

  runApp(const BangumiApp());
}

/// BangumiApp：组件或数据结构定义。
class BangumiApp extends StatefulWidget {
  const BangumiApp({super.key});

  @override
  State<BangumiApp> createState() => _BangumiAppState();
}

/// _BangumiAppState：组件或数据结构定义。
class _BangumiAppState extends State<BangumiApp> {
  final AppStateStore _appStateStore = AppStateStore();
  ThemeMode _themeMode = ThemeMode.system;

  @override
  /// 初始化状态、监听与启动流程。
  void initState() {
    super.initState();
    unawaited(_loadThemeModeFromSettings());
  }

  Future<void> _loadThemeModeFromSettings() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    final dynamic settingsRaw = state[settingsStorageKey];
    String modeRaw = '';
    if (settingsRaw is Map) {
      modeRaw = (settingsRaw[themeModeSettingKey] ?? '').toString();
    }
    final ThemeMode restoredMode = themeModeFromStorageValue(modeRaw);
    if (!mounted || restoredMode == _themeMode) {
      return;
    }
    setState(() {
      _themeMode = restoredMode;
    });
  }

  
  void _onThemeModeChanged(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    setState(() {
      _themeMode = mode;
    });
  }


  @override
  /// 构建当前组件的界面结构。
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CyberBangumi Pro',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _themeMode,
      home: BangumiHomePage(
        initialThemeMode: _themeMode,
        onThemeModeChanged: _onThemeModeChanged,
      ),
    );
  }
}

/// SubjectItem：组件或数据结构定义。
class SubjectItem {
  const SubjectItem({
    required this.subjectId,
    required this.subjectUrl,
    required this.nameCn,
    required this.nameOrigin,
    required this.coverUrl,
    this.updateTime = '',
    this.localCoverPath = '',
  });

  final String subjectId;
  final String subjectUrl;
  final String nameCn;
  final String nameOrigin;
  final String coverUrl;
  final String updateTime;
  final String localCoverPath;

  
  static String _readJsonString(dynamic value) {
    if (value == null) {
      return '';
    }
    final String text = value.toString().trim();
    return text == 'null' ? '' : text;
  }

  String get displayName => nameCn.isNotEmpty ? nameCn : nameOrigin;

  factory SubjectItem.fromJson(Map<String, dynamic> json) {
    return SubjectItem(
      subjectId: _readJsonString(json['subject_id']),
      subjectUrl: _readJsonString(json['subject_url']),
      nameCn: _readJsonString(json['name_cn']),
      nameOrigin: _readJsonString(json['name_origin']),
      coverUrl: _readJsonString(json['cover_url']),
      updateTime: _readJsonString(json['update_time']),
    );
  }

  SubjectItem copyWith({
    String? subjectId,
    String? subjectUrl,
    String? nameCn,
    String? nameOrigin,
    String? coverUrl,
    String? updateTime,
    String? localCoverPath,
  }) {
    return SubjectItem(
      subjectId: subjectId ?? this.subjectId,
      subjectUrl: subjectUrl ?? this.subjectUrl,
      nameCn: nameCn ?? this.nameCn,
      nameOrigin: nameOrigin ?? this.nameOrigin,
      coverUrl: coverUrl ?? this.coverUrl,
      updateTime: updateTime ?? this.updateTime,
      localCoverPath: localCoverPath ?? this.localCoverPath,
    );
  }

  
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'subject_id': subjectId,
      'subject_url': subjectUrl,
      'name_cn': nameCn,
      'name_origin': nameOrigin,
      'cover_url': coverUrl,
      'update_time': updateTime,
    };
  }
}

/// DaySchedule：组件或数据结构定义。
class DaySchedule {
  const DaySchedule({required this.weekday, required this.items});

  final String weekday;
  final List<SubjectItem> items;

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawItems =
        (json['items'] as List<dynamic>?) ?? <dynamic>[];
    return DaySchedule(
      weekday: (json['weekday'] ?? '').toString(),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(SubjectItem.fromJson)
          .toList(),
    );
  }

  
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'weekday': weekday,
      'items': items.map((SubjectItem item) => item.toJson()).toList(),
    };
  }
}

/// SubjectProgress：组件或数据结构定义。
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

/// SubjectBasicInfo：组件或数据结构定义。
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

/// EpisodeProgress：组件或数据结构定义。
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

/// EpisodeCommentChartLayout：组件或数据结构定义。
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

/// CoverCacheManager：组件或数据结构定义。
class CoverCacheManager {
  static const List<String> _knownExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'img',
  ];

  Directory? _cacheDir;

  
  Directory _resolveCacheBaseDir() {
    // Always persist under the workspace/project directory.
    return Directory.current;
  }

  Future<Directory> _ensureCacheDir() async {
    if (_cacheDir != null) {
      return _cacheDir!;
    }

    final Directory appDir = _resolveCacheBaseDir();
    final Directory cacheDir = Directory(
      '${appDir.path}${Platform.pathSeparator}cover_cache',
    );
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDir = cacheDir;
    return cacheDir;
  }

  Future<bool> isCacheDirMissingInAppDir() async {
    final Directory appDir = _resolveCacheBaseDir();
    final Directory cacheDir = Directory(
      '${appDir.path}${Platform.pathSeparator}cover_cache',
    );
    return !await cacheDir.exists();
  }

  
  String _fileExtFromUrl(String imageUrl) {
    final Uri? uri = Uri.tryParse(imageUrl);
    if (uri == null) {
      return 'img';
    }
    final String path = uri.path.toLowerCase();
    if (path.endsWith('.jpg')) return 'jpg';
    if (path.endsWith('.jpeg')) return 'jpeg';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    return 'img';
  }

  Future<String?> getCachedPath(String subjectId) async {
    if (subjectId.isEmpty) {
      return null;
    }
    final Directory primaryDir = await _ensureCacheDir();
    final Directory workspaceDir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}cover_cache',
    );

    final List<Directory> candidateDirs = <Directory>[primaryDir];
    if (workspaceDir.path != primaryDir.path) {
      candidateDirs.add(workspaceDir);
    }

    for (final Directory dir in candidateDirs) {
      for (final String ext in _knownExtensions) {
        final File file = File(
          '${dir.path}${Platform.pathSeparator}$subjectId.$ext',
        );
        if (await file.exists()) {
          return file.path;
        }
      }
    }
    return null;
  }

  Future<String?> ensureCached({
    required String subjectId,
    required String imageUrl,
    required Future<http.Response> Function(String url) fetch,
  }) async {
    if (subjectId.isEmpty || imageUrl.isEmpty) {
      return null;
    }

    final String? cached = await getCachedPath(subjectId);
    if (cached != null) {
      return cached;
    }

    final Directory dir = await _ensureCacheDir();
    final String ext = _fileExtFromUrl(imageUrl);
    final File file = File(
      '${dir.path}${Platform.pathSeparator}$subjectId.$ext',
    );

    final http.Response response = await fetch(imageUrl);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<int> clearAll() async {
    final Directory dir = await _ensureCacheDir();
    if (!await dir.exists()) {
      return 0;
    }

    int deleted = 0;
    await for (final FileSystemEntity entry in dir.list()) {
      if (entry is File) {
        await entry.delete();
        deleted += 1;
      }
    }
    return deleted;
  }
}

/// CalendarCacheManager：组件或数据结构定义。
class CalendarCacheManager {
  static const String _cacheFileName = 'calendar_cache.json';

  File? _cacheFile;

  
  Directory _resolveCalendarCacheDir() {
    // Always persist under the workspace/project directory.
    return Directory.current;
  }

  Future<File> _ensureCacheFile() async {
    if (_cacheFile != null) {
      return _cacheFile!;
    }

    final Directory targetDir = _resolveCalendarCacheDir();
    _cacheFile = File(
      '${targetDir.path}${Platform.pathSeparator}$_cacheFileName',
    );
    return _cacheFile!;
  }

  Future<List<DaySchedule>> load() async {
    final File file = await _ensureCacheFile();
    if (!await file.exists()) {
      return <DaySchedule>[];
    }

    final String raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return <DaySchedule>[];
    }

    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return <DaySchedule>[];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DaySchedule.fromJson)
        .toList();
  }

  Future<void> save(List<DaySchedule> schedule) async {
    final File file = await _ensureCacheFile();
    final String raw = const JsonEncoder.withIndent(
      '  ',
    ).convert(schedule.map((DaySchedule day) => day.toJson()).toList());
    await file.writeAsString(raw, flush: true);
  }
}

/// AppStateStore：组件或数据结构定义。
class AppStateStore {
  static const String _stateFileName = 'app_state.json';

  
  File _resolveStateFile() {
    return File(
      '${Directory.current.path}${Platform.pathSeparator}$_stateFileName',
    );
  }

  Future<Map<String, dynamic>> readState() async {
    final File file = _resolveStateFile();
    if (!await file.exists()) {
      return <String, dynamic>{};
    }

    try {
      final String raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> writeState(Map<String, dynamic> state) async {
    final File file = _resolveStateFile();
    final String raw = const JsonEncoder.withIndent('  ').convert(state);
    await file.writeAsString(raw, flush: true);
  }
}

/// WatchArchiveEntry：组件或数据结构定义。
class WatchArchiveEntry {
  const WatchArchiveEntry({
    required this.subjectId,
    required this.nameCn,
    required this.nameJp,
    required this.quarter,
    required this.text,
    required this.archivedAt,
  });

  final String subjectId;
  final String nameCn;
  final String nameJp;
  final String quarter;
  final String text;
  final String archivedAt;

  factory WatchArchiveEntry.fromSubject(
    SubjectItem item, {
    required String quarter,
  }) {
    final String cn = item.nameCn.trim();
    final String jpRaw = item.nameOrigin.trim();
    final String jp = jpRaw.isNotEmpty
        ? jpRaw
        : (item.displayName.isNotEmpty ? item.displayName : item.subjectId);
    final String text = cn.isNotEmpty
        ? '$cn / $jp（$quarter）'
        : '$jp（$quarter）';

    return WatchArchiveEntry(
      subjectId: item.subjectId,
      nameCn: cn,
      nameJp: jp,
      quarter: quarter,
      text: text,
      archivedAt: DateTime.now().toIso8601String(),
    );
  }

  factory WatchArchiveEntry.fromJson(Map<String, dynamic> json) {
    return WatchArchiveEntry(
      subjectId: (json['subject_id'] ?? '').toString(),
      nameCn: (json['name_cn'] ?? '').toString(),
      nameJp: (json['name_jp'] ?? '').toString(),
      quarter: (json['quarter'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      archivedAt: (json['archived_at'] ?? '').toString(),
    );
  }

  
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'subject_id': subjectId,
      'name_cn': nameCn,
      'name_jp': nameJp,
      'quarter': quarter,
      'text': text,
      'archived_at': archivedAt,
    };
  }
}

/// WatchArchiveStore：组件或数据结构定义。
class WatchArchiveStore {
  static const String _archiveFileName = 'watch_archive.json';

  
  File _resolveArchiveFile() {
    return File(
      '${Directory.current.path}${Platform.pathSeparator}$_archiveFileName',
    );
  }

  Future<List<WatchArchiveEntry>> load() async {
    final File file = _resolveArchiveFile();
    if (!await file.exists()) {
      await file.writeAsString('[]', flush: true);
      return <WatchArchiveEntry>[];
    }

    try {
      final String raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return <WatchArchiveEntry>[];
      }
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return <WatchArchiveEntry>[];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(WatchArchiveEntry.fromJson)
          .toList();
    } catch (_) {
      return <WatchArchiveEntry>[];
    }
  }

  Future<void> save(List<WatchArchiveEntry> entries) async {
    final File file = _resolveArchiveFile();
    final String raw = const JsonEncoder.withIndent('  ').convert(
      entries.map((WatchArchiveEntry e) => e.toJson()).toList(),
    );
    await file.writeAsString(raw, flush: true);
  }

  Future<void> appendEntries(List<WatchArchiveEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }
    final List<WatchArchiveEntry> current = await load();
    current.addAll(entries);
    await save(current);
  }
}

/// BangumiService：组件或数据结构定义。
class BangumiService {
  BangumiService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _insecureTlsClient = IOClient(_createInsecureHttpClient());

  static const Duration _minRequestInterval = Duration(milliseconds: 800);
  static const Duration _apiHealthCacheTtl = Duration(minutes: 3);
  static const Set<String> _tlsFallbackHosts = <String>{
    'bangumi.tv',
    'api.bgm.tv',
    'bgmlist.com',
    'lain.bgm.tv',
  };

  final http.Client _client;
  final bool _ownsClient;
  final http.Client _insecureTlsClient;
  final ValueNotifier<int> _activeRequests = ValueNotifier<int>(0);
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _requestQueue = Future<void>.value();
  int apiFastRetryBaseDelayMs = 120;
  String apiUserAgent = appUserAgent;
  bool allowInsecureTlsFallback = true;
  bool? _apiAvailableCache;
  DateTime? _apiAvailableCheckedAt;
  void Function(String message)? onNetworkLog;

  ValueNotifier<int> get activeRequests => _activeRequests;

  
  void _logNetwork(String message) {
    onNetworkLog?.call('网络: $message');
  }

  String get effectiveApiUserAgent {
    final String candidate = apiUserAgent.trim();
    return candidate.isEmpty ? appUserAgent : candidate;
  }

  Map<String, String> get _apiRequestHeaders => <String, String>{
        'User-Agent': apiUserAgent.trim().isEmpty ? appUserAgent : apiUserAgent,
        'Accept': 'application/json',
      };

  
  String _describeUrl(String rawUrl) {
    try {
      final Uri uri = Uri.parse(rawUrl);
      final String path = uri.path.isEmpty ? '/' : uri.path;
      return '${uri.scheme}://${uri.host}$path';
    } catch (_) {
      return rawUrl;
    }
  }

  static HttpClient _createInsecureHttpClient() {
    final HttpClient client = HttpClient();
    client.badCertificateCallback = (
      X509Certificate cert,
      String host,
      int port,
    ) => true;
    return client;
  }

  bool _isTlsCertificateFailure(Object error) {
    final String message = error.toString().toUpperCase();
    return message.contains('HANDSHAKEEXCEPTION') ||
        message.contains('CERTIFICATE_VERIFY_FAILED');
  }

  bool _shouldTryInsecureTlsFallback(Uri uri, Object error) {
    if (!allowInsecureTlsFallback || uri.scheme.toLowerCase() != 'https') {
      return false;
    }
    if (!_tlsFallbackHosts.contains(uri.host.toLowerCase())) {
      return false;
    }
    return _isTlsCertificateFailure(error);
  }

  Future<http.Response> _getWithTlsFallback(
    Uri uri, {
    required Map<String, String> headers,
    required String purpose,
  }) async {
    try {
      return await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      if (!_shouldTryInsecureTlsFallback(uri, e)) {
        rethrow;
      }

      _logNetwork(
        'TLS 证书校验失败[$purpose] ${_describeUrl(uri.toString())}，'
        '对该域名启用兼容重试（不安全 TLS）',
      );
      return _insecureTlsClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
    _insecureTlsClient.close();
    _activeRequests.dispose();
  }

  Future<T> _runTrackedRequest<T>(Future<T> Function() operation) async {
    _activeRequests.value += 1;
    try {
      return await operation();
    } finally {
      if (_activeRequests.value > 0) {
        _activeRequests.value -= 1;
      }
    }
  }

  
  Future<void> _waitForRequestSlot() {
    _requestQueue = _requestQueue.then((_) async {
      final Duration elapsed = DateTime.now().difference(_lastRequestAt);
      if (elapsed < _minRequestInterval) {
        await Future<void>.delayed(_minRequestInterval - elapsed);
      }
      _lastRequestAt = DateTime.now();
    });
    return _requestQueue;
  }

  
  String _normalizeImageUrl(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return '';
    }

    final String unescaped = value.replaceAll('&amp;', '&');

    if (unescaped.startsWith('//lain.bgm.tv/')) {
      return 'https:$unescaped';
    }
    if (unescaped.startsWith('http://lain.bgm.tv/')) {
      return unescaped.replaceFirst('http://', 'https://');
    }
    if (unescaped.startsWith('https://lain.bgm.tv/')) {
      return unescaped;
    }

    if (unescaped.contains('/pic/cover/')) {
      final String pathOnly = unescaped
          .replaceFirst(RegExp(r'^https?://[^/]+'), '')
          .replaceFirst(RegExp(r'^//[^/]+'), '');
      return 'https://lain.bgm.tv$pathOnly';
    }

    if (unescaped.startsWith('/r/') || unescaped.startsWith('/pic/')) {
      return 'https://lain.bgm.tv$unescaped';
    }

    if (unescaped.startsWith('//')) {
      return 'https:$unescaped';
    }
    if (unescaped.startsWith('http://')) {
      return unescaped.replaceFirst('http://', 'https://');
    }
    if (unescaped.startsWith('https://')) {
      return unescaped;
    }
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    if (value.startsWith('/')) {
      return 'https://bangumi.tv$value';
    }
    return value;
  }

  
  String _extractImageUrlFromElement(dom.Element node) {
    final String directSrc =
        node.attributes['src']?.trim() ??
        node.attributes['data-src']?.trim() ??
        node.attributes['data-cfsrc']?.trim() ??
        node.attributes['data-original']?.trim() ??
        '';
    if (directSrc.isNotEmpty) {
      return _normalizeImageUrl(directSrc);
    }

    final String srcSet = node.attributes['srcset']?.trim() ?? '';
    if (srcSet.isNotEmpty) {
      final String first = srcSet
          .split(',')
          .first
          .trim()
          .split(' ')
          .first
          .trim();
      if (first.isNotEmpty) {
        return _normalizeImageUrl(first);
      }
    }

    final String style = node.attributes['style']?.trim() ?? '';
    if (style.isNotEmpty) {
      final RegExpMatch? styleMatch = RegExp(
        'background(?:-image)?\\s*:\\s*url\\((?:["\\\'])?(.*?)(?:["\\\'])?\\)',
        caseSensitive: false,
      ).firstMatch(style);
      if (styleMatch != null) {
        final String url = (styleMatch.group(1) ?? '').trim();
        if (url.isNotEmpty) {
          return _normalizeImageUrl(url);
        }
      }
    }

    return '';
  }

  
  String _extractCoverUrlFromNode(dom.Element animeNode) {
    final List<String> selectors = <String>[
      'a.thumbTip',
      'a.thumbTip img',
      'span.image img',
      'a.thumbTip span.image',
      '.subjectCover img',
      '.subjectCover',
      'a.cover img',
      'span.cover img',
      'img.cover',
      'a img',
      'img',
    ];

    for (final String selector in selectors) {
      final dom.Element? node = animeNode.querySelector(selector);
      if (node == null) {
        continue;
      }

      final String source = _extractImageUrlFromElement(node);
      if (source.isNotEmpty) {
        return source;
      }
    }

    final RegExpMatch? htmlMatch = RegExp(
      '(https?:)?//[^\\s"\\\']+/pic/cover/[^\\s"\\\']+',
      caseSensitive: false,
    ).firstMatch(animeNode.innerHtml);
    if (htmlMatch != null) {
      return _normalizeImageUrl(htmlMatch.group(0) ?? '');
    }

    final RegExpMatch? relativeMatch = RegExp(
      '/r/\\d+/pic/cover/[^\\s"\\\']+',
      caseSensitive: false,
    ).firstMatch(animeNode.innerHtml);
    if (relativeMatch != null) {
      return _normalizeImageUrl(relativeMatch.group(0) ?? '');
    }

    return '';
  }

  Future<String> _getWithRetry(
    String url, {
    required String purpose,
    Map<String, String> headers = requestHeaders,
    bool respectRateLimit = true,
    int retryBaseDelayMs = 800,
  }) async {
    Object? lastError;
    _logNetwork('开始抓取[$purpose] ${_describeUrl(url)}');
    if (url.startsWith(bangumiApiBaseUrl)) {
      _logNetwork('当前 API UA: $effectiveApiUserAgent');
    }
    for (int i = 0; i < 3; i++) {
      try {
        _logNetwork('尝试 ${i + 1}/3 [$purpose] ${_describeUrl(url)}');
        if (respectRateLimit) {
          await _waitForRequestSlot();
        }
        final Uri requestUri = Uri.parse(url);
        final http.Response response = await _runTrackedRequest(
          () => _getWithTlsFallback(
            requestUri,
            headers: headers,
            purpose: purpose,
          ),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _logNetwork(
            '抓取成功[$purpose] ${_describeUrl(url)} '
            '(HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes)',
          );
          return utf8.decode(response.bodyBytes);
        }
        if (response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          _logNetwork(
            '抓取重试[$purpose] ${_describeUrl(url)} '
            '(HTTP ${response.statusCode})',
          );
          throw Exception('HTTP ${response.statusCode}');
        }
        _logNetwork(
          '抓取失败[$purpose] ${_describeUrl(url)} '
          '(HTTP ${response.statusCode})',
        );
        throw Exception('请求失败，状态码: ${response.statusCode}');
      } catch (e) {
        lastError = e;
        _logNetwork('抓取异常[$purpose] ${_describeUrl(url)} ($e)');
        await Future<void>.delayed(
          Duration(milliseconds: retryBaseDelayMs * (i + 1)),
        );
      }
    }
    _logNetwork('抓取终止[$purpose] ${_describeUrl(url)} (${lastError ?? '未知错误'})');
    throw Exception(lastError?.toString() ?? '请求失败');
  }

  Future<http.Response> fetchImageWithRetry(
    String url, {
    bool respectRateLimit = true,
    String purpose = '抓取图片资源',
  }) async {
    Object? lastError;
    _logNetwork('开始抓取[$purpose] ${_describeUrl(url)}');
    for (int i = 0; i < 3; i++) {
      try {
        _logNetwork('尝试 ${i + 1}/3 [$purpose] ${_describeUrl(url)}');
        if (respectRateLimit) {
          await _waitForRequestSlot();
        }
        final Uri requestUri = Uri.parse(url);
        final http.Response response = await _runTrackedRequest(
          () => _getWithTlsFallback(
            requestUri,
            headers: imageRequestHeaders,
            purpose: purpose,
          ),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _logNetwork(
            '抓取成功[$purpose] ${_describeUrl(url)} '
            '(HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes)',
          );
          return response;
        }
        if (response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          _logNetwork(
            '抓取重试[$purpose] ${_describeUrl(url)} '
            '(HTTP ${response.statusCode})',
          );
          throw Exception('HTTP ${response.statusCode}');
        }
        _logNetwork(
          '抓取失败[$purpose] ${_describeUrl(url)} '
          '(HTTP ${response.statusCode})',
        );
        return response;
      } catch (e) {
        lastError = e;
        _logNetwork('抓取异常[$purpose] ${_describeUrl(url)} ($e)');
        await Future<void>.delayed(Duration(milliseconds: 800 * (i + 1)));
      }
    }
    _logNetwork('抓取终止[$purpose] ${_describeUrl(url)} (${lastError ?? '未知错误'})');
    throw Exception(lastError?.toString() ?? '图片请求失败');
  }

  Future<List<DaySchedule>> fetchCalendarSchedule() async {
    final String pageText = await _getWithRetry(
      calendarUrl,
      purpose: '抓取 Bangumi 日历页面',
    );
    return parseDailySchedule(pageText);
  }

  Future<bool> isApiAvailable({bool forceRefresh = false}) async {
    final DateTime now = DateTime.now();
    if (!forceRefresh &&
        _apiAvailableCache != null &&
        _apiAvailableCheckedAt != null &&
        now.difference(_apiAvailableCheckedAt!) < _apiHealthCacheTtl) {
      return _apiAvailableCache!;
    }

    try {
      final String body = await _getWithRetry(
        '$bangumiApiBaseUrl/v0/subjects/1',
        purpose: '探测 Bangumi API 可用性',
        headers: _apiRequestHeaders,
        respectRateLimit: false,
        retryBaseDelayMs: apiFastRetryBaseDelayMs,
      );
      final dynamic decoded = jsonDecode(body);
      final bool ok = decoded is Map<String, dynamic> && decoded['id'] != null;
      _apiAvailableCache = ok;
      _apiAvailableCheckedAt = now;
      return ok;
    } catch (_) {
      _apiAvailableCache = false;
      _apiAvailableCheckedAt = now;
      return false;
    }
  }

  Future<String> fetchBgmListOnAirJson() async {
    return _getWithRetry(bgmListOnAirApiUrl, purpose: '抓取 BGMLIST 全部番组 JSON');
  }

  DateTime? _toJstDateTimeFromIso(String isoText) {
    if (isoText.isEmpty) {
      return null;
    }
    try {
      final DateTime utc = DateTime.parse(isoText).toUtc();
      return utc.add(const Duration(hours: 9));
    } catch (_) {
      return null;
    }
  }

  
  String _toJstTimeFromIso(String isoText) {
    final DateTime? jst = _toJstDateTimeFromIso(isoText);
    if (jst == null) {
      return '';
    }
    final String hh = jst.hour.toString().padLeft(2, '0');
    final String mm = jst.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  
  String _extractJstTimeFromBgmListItem(Map<String, dynamic> item) {
    final String broadcast = (item['broadcast'] as String? ?? '').trim();
    if (broadcast.isNotEmpty) {
      final RegExpMatch? match = RegExp(r'^R/([^/]+)/').firstMatch(broadcast);
      final String fromBroadcast = _toJstTimeFromIso(
        (match?.group(1) ?? '').trim(),
      );
      if (fromBroadcast.isNotEmpty) {
        return fromBroadcast;
      }
    }

    final String begin = (item['begin'] as String? ?? '').trim();
    return _toJstTimeFromIso(begin);
  }

  
  Iterable<String> _extractJpTitlesFromBgmListItem(Map<String, dynamic> item) {
    final Set<String> titles = <String>{};

    final String mainTitle = (item['title'] as String? ?? '').trim();
    if (mainTitle.isNotEmpty) {
      titles.add(mainTitle);
    }

    final dynamic titleTranslate = item['titleTranslate'];
    if (titleTranslate is Map) {
      final dynamic ja = titleTranslate['ja'];
      if (ja is List) {
        for (final dynamic raw in ja) {
          final String value = raw?.toString().trim() ?? '';
          if (value.isNotEmpty) {
            titles.add(value);
          }
        }
      }
    }

    return titles.toList(growable: false);
  }

  
  List<BgmListOnAirEntry> parseBgmListOnAirEntries(String jsonText) {
    if (jsonText.trim().isEmpty) {
      return <BgmListOnAirEntry>[];
    }

    try {
      final dynamic decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return <BgmListOnAirEntry>[];
      }

      final dynamic itemsRaw = decoded['items'];
      if (itemsRaw is! List) {
        return <BgmListOnAirEntry>[];
      }

      final List<BgmListOnAirEntry> entries = <BgmListOnAirEntry>[];
      for (final dynamic raw in itemsRaw) {
        if (raw is! Map<String, dynamic>) {
          continue;
        }

        final String timeText = _extractJstTimeFromBgmListItem(raw);
        if (timeText.isEmpty) {
          continue;
        }

        final List<String> jpTitles = _extractJpTitlesFromBgmListItem(
          raw,
        ).where((String title) => title.trim().isNotEmpty).toList();
        if (jpTitles.isEmpty) {
          continue;
        }

        entries.add(BgmListOnAirEntry(timeJst: timeText, jpTitles: jpTitles));
      }

      return entries;
    } catch (_) {
      return <BgmListOnAirEntry>[];
    }
  }

  String _extractBangumiIdFromBgmListItem(Map<String, dynamic> item) {
    final dynamic sitesRaw = item['sites'];
    if (sitesRaw is! List) {
      return '';
    }

    for (final dynamic siteRaw in sitesRaw) {
      if (siteRaw is! Map<String, dynamic>) {
        continue;
      }
      final String site = _readString(siteRaw['site']).toLowerCase();
      if (site == 'bangumi' || site == 'bangumi.tv') {
        final String id = _readString(siteRaw['id']);
        if (RegExp(r'^\d+$').hasMatch(id)) {
          return id;
        }
      }
    }

    return '';
  }

  String _extractCnTitleFromBgmListItem(Map<String, dynamic> item) {
    final dynamic titleTranslate = item['titleTranslate'];
    if (titleTranslate is! Map) {
      return '';
    }

    for (final String key in <String>['zh-Hans', 'zh-Hant', 'zh']) {
      final dynamic raw = titleTranslate[key];
      if (raw is List) {
        for (final dynamic one in raw) {
          final String text = one?.toString().trim() ?? '';
          if (text.isNotEmpty) {
            return text;
          }
        }
      }
    }

    return '';
  }

  String _extractCoverUrlFromBgmListItem(Map<String, dynamic> item) {
    final dynamic imagesRaw = item['images'];
    if (imagesRaw is! Map<String, dynamic>) {
      return '';
    }

    for (final String key in <String>[
      'common',
      'large',
      'medium',
      'small',
      'grid',
    ]) {
      final String url = _normalizeImageUrl(_readString(imagesRaw[key]));
      if (url.isNotEmpty) {
        return url;
      }
    }

    return '';
  }

  DateTime? _extractBroadcastStartJstFromBgmListItem(Map<String, dynamic> item) {
    final String broadcast = _readString(item['broadcast']);
    if (broadcast.isNotEmpty) {
      final RegExpMatch? match = RegExp(r'^R/([^/]+)/').firstMatch(broadcast);
      final DateTime? start = _toJstDateTimeFromIso(
        (match?.group(1) ?? '').trim(),
      );
      if (start != null) {
        return start;
      }
    }
    return null;
  }

  DateTime? _extractBeginJstFromBgmListItem(Map<String, dynamic> item) {
    final String begin = _readString(item['begin']);
    if (begin.isNotEmpty) {
      final DateTime? beginJst = _toJstDateTimeFromIso(begin);
      if (beginJst != null) {
        return beginJst;
      }
    }
    return _extractBroadcastStartJstFromBgmListItem(item);
  }

  int? _extractBroadcastPeriodDaysFromBgmListItem(Map<String, dynamic> item) {
    final String broadcast = _readString(item['broadcast']);
    if (broadcast.isEmpty) {
      return null;
    }

    final RegExpMatch? match = RegExp(r'^R/[^/]+/P(\d+)([DWM])$').firstMatch(
      broadcast,
    );
    if (match == null) {
      return null;
    }

    final int? amount = int.tryParse(match.group(1) ?? '');
    final String unit = match.group(2) ?? '';
    if (amount == null || amount <= 0) {
      return null;
    }

    if (unit == 'D') {
      return amount;
    }
    if (unit == 'W') {
      return amount * 7;
    }

    return null;
  }

  List<BgmListScheduleCandidate> parseBgmListScheduleCandidates(String jsonText) {
    if (jsonText.trim().isEmpty) {
      return <BgmListScheduleCandidate>[];
    }

    try {
      final dynamic decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return <BgmListScheduleCandidate>[];
      }

      final dynamic itemsRaw = decoded['items'];
      if (itemsRaw is! List) {
        return <BgmListScheduleCandidate>[];
      }

      final List<BgmListScheduleCandidate> result = <BgmListScheduleCandidate>[];
      for (final dynamic raw in itemsRaw) {
        if (raw is! Map<String, dynamic>) {
          continue;
        }

        final String subjectId = _extractBangumiIdFromBgmListItem(raw);
        if (subjectId.isEmpty) {
          continue;
        }

        final String titleJp = _readString(raw['title']);
        if (titleJp.isEmpty) {
          continue;
        }

        final DateTime? beginJst = _extractBeginJstFromBgmListItem(raw);
        if (beginJst == null) {
          continue;
        }

        final DateTime? broadcastStartJst =
            _extractBroadcastStartJstFromBgmListItem(raw);
        final DateTime weekdaySource = broadcastStartJst ?? beginJst;
        final String weekdayJst = weekdayMap[weekdaySource.weekday] ?? '';
        if (weekdayJst.isEmpty) {
          continue;
        }

        final String updateTimeJst = _extractJstTimeFromBgmListItem(raw);
        if (updateTimeJst.isEmpty) {
          continue;
        }

        final int? periodDays = _extractBroadcastPeriodDaysFromBgmListItem(raw);
        if (periodDays == null || periodDays <= 0) {
          continue;
        }

        result.add(
          BgmListScheduleCandidate(
            subjectId: subjectId,
            subjectUrl: 'https://bangumi.tv/subject/$subjectId',
            titleJp: titleJp,
            titleCn: _extractCnTitleFromBgmListItem(raw),
            coverUrl: _extractCoverUrlFromBgmListItem(raw),
            weekdayJst: weekdayJst,
            updateTimeJst: updateTimeJst,
            beginJst: beginJst,
            periodDays: periodDays,
          ),
        );
      }

      return result;
    } catch (_) {
      return <BgmListScheduleCandidate>[];
    }
  }

  
  String _extractSubjectId(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final RegExp pureNumber = RegExp(r'^\d+$');
    if (pureNumber.hasMatch(trimmed)) {
      return trimmed;
    }

    final RegExp pathPattern = RegExp(r'/subject/(\d+)');
    final RegExpMatch? pathMatch = pathPattern.firstMatch(trimmed);
    if (pathMatch != null) {
      return pathMatch.group(1) ?? '';
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final RegExpMatch? uriMatch = pathPattern.firstMatch(uri.path);
      if (uriMatch != null) {
        return uriMatch.group(1) ?? '';
      }
    }

    return '';
  }

  
  String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    final String text = value.toString().trim();
    return text == 'null' ? '' : text;
  }

  
  int? _readInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    return int.tryParse(value.toString().trim());
  }

  
  double? _readDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString().trim());
  }

  
  DateTime? _readDate(String rawDate) {
    final String value = rawDate.trim();
    if (value.isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  
  String _pickBestImageUrlFromSubjectApi(Map<String, dynamic> subjectJson) {
    final dynamic imagesRaw = subjectJson['images'];
    if (imagesRaw is! Map<String, dynamic>) {
      return '';
    }

    for (final String key in <String>[
      'common',
      'large',
      'medium',
      'small',
      'grid',
    ]) {
      final String url = _normalizeImageUrl(_readString(imagesRaw[key]));
      if (url.isNotEmpty) {
        return url;
      }
    }
    return '';
  }

  Future<Map<String, dynamic>?> _fetchSubjectFromApi(String subjectId) async {
    if (subjectId.isEmpty) {
      return null;
    }

    final String body = await _getWithRetry(
      '$bangumiApiBaseUrl/v0/subjects/$subjectId',
      purpose: '抓取 Bangumi API 条目信息',
      headers: _apiRequestHeaders,
      respectRateLimit: false,
      retryBaseDelayMs: apiFastRetryBaseDelayMs,
    );

    final dynamic decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  }

  Future<int?> fetchSubjectTotalEpisodes(String subjectId) async {
    final Map<String, dynamic>? subject = await _fetchSubjectFromApi(subjectId);
    if (subject == null || subject.isEmpty) {
      return null;
    }

    final int? total = _readInt(subject['total_episodes']) ?? _readInt(subject['eps']);
    if (total == null || total <= 0) {
      return null;
    }
    return total;
  }

  Future<List<Map<String, dynamic>>> _fetchMainEpisodesFromApi(
    String subjectId,
  ) async {
    if (subjectId.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final String body = await _getWithRetry(
      '$bangumiApiBaseUrl/v0/episodes?subject_id=$subjectId&type=0&limit=200&offset=0',
      purpose: '抓取 Bangumi API 分集列表',
      headers: _apiRequestHeaders,
      respectRateLimit: false,
      retryBaseDelayMs: apiFastRetryBaseDelayMs,
    );

    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return <Map<String, dynamic>>[];
    }
    final dynamic data = decoded['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }

    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<SubjectProgress?> _tryFetchSubjectProgressViaApi(
    String targetUrl, {
    String scheduleTime = '',
    String scheduleWeekday = '',
    int displayTimezoneOffsetMinutes = BroadcastTimeConverter.jstOffsetMinutes,
  }
  ) async {
    final String subjectId = _extractSubjectId(targetUrl);
    if (subjectId.isEmpty) {
      return null;
    }

    Map<String, dynamic>? subject;
    List<Map<String, dynamic>> episodes = <Map<String, dynamic>>[];

    await Future.wait<void>(<Future<void>>[
      (() async {
        subject = await _fetchSubjectFromApi(subjectId);
      })(),
      (() async {
        episodes = await _fetchMainEpisodesFromApi(subjectId);
      })(),
    ]);

    if (subject == null || subject!.isEmpty) {
      return null;
    }
    if (episodes.isEmpty) {
      return null;
    }
    final Map<String, dynamic> subjectData = subject!;

    final List<Map<String, dynamic>>
    sorted = List<Map<String, dynamic>>.from(episodes)
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final double aNo = _readDouble(a['ep']) ?? _readDouble(a['sort']) ?? 0;
        final double bNo = _readDouble(b['ep']) ?? _readDouble(b['sort']) ?? 0;
        return aNo.compareTo(bNo);
      });

    final int normalizedDisplayOffset =
      BroadcastTimeConverter.normalizeTimezoneOffsetMinutes(
        displayTimezoneOffsetMinutes,
      );
    final DateTime nowInDisplay =
      DateTime.now().toUtc().add(Duration(minutes: normalizedDisplayOffset));
    final DateTime todayStartInDisplay = DateTime.utc(
      nowInDisplay.year,
      nowInDisplay.month,
      nowInDisplay.day,
    );

    int airedCount = 0;
    int? latestAiredEp;
    String? latestAiredDisplayTitle;
    DateTime? latestAiredAtInDisplay;
    int? nextEp;
    final List<int> episodeCommentCounts = <int>[];
    final Map<int, String> episodeTitleByEp = <int, String>{};

    for (final Map<String, dynamic> ep in sorted) {
      final int epNo = (_readDouble(ep['ep']) ?? _readDouble(ep['sort']) ?? 0)
          .round();
      final String airdateText = _readString(ep['airdate']);
      final DateTime? airdate = _readDate(airdateText);
      final int commentCount = _readInt(ep['comment']) ?? 0;
      episodeCommentCounts.add(math.max(commentCount, 0));

      DateTime? airedAtInDisplay;
      bool isAired;
      if (airdate == null) {
        isAired = false;
      } else if (scheduleTime.trim().isNotEmpty) {
        airedAtInDisplay = BroadcastTimeConverter.resolveEpisodeBroadcastInDisplayTime(
          airdateJst: DateTime(airdate.year, airdate.month, airdate.day),
          displayTime: scheduleTime,
          displayOffsetMinutes: normalizedDisplayOffset,
          displayWeekday: scheduleWeekday,
        );

        if (airedAtInDisplay != null) {
          isAired = !airedAtInDisplay.isAfter(nowInDisplay);
        } else {
          isAired = !DateTime.utc(
            airdate.year,
            airdate.month,
            airdate.day,
          ).isAfter(todayStartInDisplay);
        }
      } else {
        isAired = !DateTime.utc(
          airdate.year,
          airdate.month,
          airdate.day,
        ).isAfter(todayStartInDisplay);
      }

      final String cn = _readString(ep['name_cn']);
      final String origin = _readString(ep['name']);
      final String display = cn.isNotEmpty ? cn : origin;
      if (epNo > 0 && display.isNotEmpty) {
        episodeTitleByEp[epNo] = display;
      }

      if (isAired) {
        airedCount += 1;
        if (epNo > 0) {
          latestAiredEp = epNo;
          latestAiredAtInDisplay = airedAtInDisplay;
        }

        if (display.isNotEmpty) {
          latestAiredDisplayTitle = display;
        }
      } else if (nextEp == null && epNo > 0) {
        nextEp = epNo;
      }
    }

    final int totalEpsListed = sorted.length;
    final Map<String, dynamic>? ratingData =
        subjectData['rating'] as Map<String, dynamic>?;
    final double? ratingScore = _readDouble(ratingData?['score']);
    final int? totalEpsDeclared =
        _readInt(subjectData['total_episodes']) ?? _readInt(subjectData['eps']);
    final int? totalEps =
        totalEpsDeclared ?? (totalEpsListed > 0 ? totalEpsListed : null);

    final String progressText = totalEps == null
        ? '未知'
        : '$airedCount/$totalEps';

    String? latestAiredAtLabel;
    if (latestAiredAtInDisplay != null) {
      final String weekday =
          weekdayMap[latestAiredAtInDisplay.weekday] ?? '';
      final String hh = latestAiredAtInDisplay.hour.toString().padLeft(2, '0');
      final String mm = latestAiredAtInDisplay.minute.toString().padLeft(2, '0');
      latestAiredAtLabel =
          '$weekday $hh:$mm ${BroadcastTimeConverter.formatUtcOffsetLabel(normalizedDisplayOffset)}';
    }

    return SubjectProgress(
      totalEpsDeclared: totalEpsDeclared,
      totalEpsListed: totalEpsListed,
      airedEps: airedCount,
      latestAiredEp: latestAiredEp,
      latestAiredCnTitle: latestAiredDisplayTitle,
      latestAiredAtLabel: latestAiredAtLabel,
      nextEp: nextEp,
      ratingScore: ratingScore,
      episodeCommentCounts: List<int>.unmodifiable(episodeCommentCounts),
      episodeTitleByEp: Map<int, String>.unmodifiable(episodeTitleByEp),
      progressText: progressText,
    );
  }

  Future<SubjectProgress> fetchSubjectProgress(
    String targetUrl, {
    String scheduleTime = '',
    String scheduleWeekday = '',
    int displayTimezoneOffsetMinutes = BroadcastTimeConverter.jstOffsetMinutes,
  }) async {
    final SubjectProgress? apiProgress = await _tryFetchSubjectProgressViaApi(
      targetUrl,
      scheduleTime: scheduleTime,
      scheduleWeekday: scheduleWeekday,
      displayTimezoneOffsetMinutes: displayTimezoneOffsetMinutes,
    );
    if (apiProgress != null) {
      return apiProgress;
    }
    throw Exception('Bangumi API 未返回有效进度数据');
  }

  Future<String> fetchSubjectCoverUrl(String subjectUrl) async {
    if (subjectUrl.isEmpty) {
      return '';
    }

    final String subjectId = _extractSubjectId(subjectUrl);
    if (subjectId.isEmpty) {
      return '';
    }

    final Map<String, dynamic>? subject = await _fetchSubjectFromApi(subjectId);
    if (subject == null) {
      return '';
    }
    return _pickBestImageUrlFromSubjectApi(subject);
  }

  
  List<DaySchedule> parseDailySchedule(String pageText) {
    final dom.Document document = html_parser.parse(pageText);
    final dom.Element? calendar = document.querySelector(
      'div.BgmCalendar ul.large',
    );
    if (calendar == null) {
      return <DaySchedule>[];
    }

    final List<DaySchedule> schedules = <DaySchedule>[];

    for (final dom.Element weekItem in calendar.querySelectorAll('li.week')) {
      final String weekday = weekItem.querySelector('dt h3')?.text.trim() ?? '';
      final List<SubjectItem> items = <SubjectItem>[];

      for (final dom.Element animeNode in weekItem.querySelectorAll(
        'dd ul.coverList > li',
      )) {
        final List<dom.Element> nameNodes = animeNode.querySelectorAll(
          'div.info p a.nav',
        );
        if (nameNodes.isEmpty) {
          continue;
        }

        final String cnName = nameNodes.isNotEmpty
            ? nameNodes[0].text.trim()
            : '';
        final String originName = nameNodes.length > 1
            ? nameNodes[1].text.trim()
            : '';
        if (cnName.isEmpty && originName.isEmpty) {
          continue;
        }

        final String subjectPath =
            nameNodes[0].attributes['href']?.trim() ?? '';
        String subjectId = '';
        final RegExpMatch? match = RegExp(
          r'^/subject/(\d+)',
        ).firstMatch(subjectPath);
        if (match != null) {
          subjectId = match.group(1) ?? '';
        }

        final String coverUrl = _extractCoverUrlFromNode(animeNode);

        items.add(
          SubjectItem(
            subjectId: subjectId,
            subjectUrl: subjectPath.isEmpty
                ? ''
                : 'https://bangumi.tv$subjectPath',
            nameCn: cnName,
            nameOrigin: originName,
            coverUrl: coverUrl,
          ),
        );
      }

      if (weekday.isNotEmpty) {
        schedules.add(DaySchedule(weekday: weekday, items: items));
      }
    }

    return schedules;
  }

  
  SubjectBasicInfo parseSubjectBasicInfo(String subjectPageText) {
    final dom.Document document = html_parser.parse(subjectPageText);
    int? totalEpsDeclared;
    String airStart = '';
    String airWeekday = '';

    for (final dom.Element li in document.querySelectorAll('#infobox li')) {
      final String text = li.text.replaceAll('\n', ' ').trim();
      if (text.startsWith('话数:') || text.startsWith('话数：')) {
        final RegExpMatch? match = RegExp(r'(\d+)').firstMatch(text);
        if (match != null) {
          totalEpsDeclared = int.tryParse(match.group(1)!);
        }
      } else if (text.startsWith('放送开始:') || text.startsWith('放送开始：')) {
        final List<String> parts = text.split(RegExp(r'[:：]'));
        if (parts.length > 1) {
          airStart = parts.sublist(1).join(':').trim();
        }
      } else if (text.startsWith('放送星期:') || text.startsWith('放送星期：')) {
        final List<String> parts = text.split(RegExp(r'[:：]'));
        if (parts.length > 1) {
          airWeekday = parts.sublist(1).join(':').trim();
        }
      }
    }

    return SubjectBasicInfo(
      totalEpsDeclared: totalEpsDeclared,
      airStart: airStart,
      airWeekday: airWeekday,
    );
  }

  
  Map<String, int> parseSubjectDiscussionCountByEpId(String subjectPageText) {
    final dom.Document document = html_parser.parse(subjectPageText);
    final Map<String, int> result = <String, int>{};

    for (final dom.Element discussLink in document.querySelectorAll(
      'a[href^="/subject/ep/"]',
    )) {
      final String href = discussLink.attributes['href']?.trim() ?? '';
      final RegExpMatch? epMatch = RegExp(
        r'^/subject/ep/(\d+)',
      ).firstMatch(href);
      if (epMatch == null) {
        continue;
      }
      final String epId = epMatch.group(1) ?? '';
      if (epId.isEmpty) {
        continue;
      }

      final dom.Element? countNode =
          discussLink.parent?.querySelector('small.na') ??
          discussLink.parent?.parent?.querySelector('small.na') ??
          discussLink.nextElementSibling;
      final String countText = countNode?.text.trim() ?? '';
      final RegExpMatch? countMatch = RegExp(r'\+?(\d+)').firstMatch(countText);
      final int? count = countMatch != null
          ? int.tryParse(countMatch.group(1) ?? '')
          : null;
      if (count == null) {
        continue;
      }

      result[epId] = count;
    }

    return result;
  }

  
  Map<String, String> parseSubjectCnTitleByEpId(String subjectPageText) {
    final dom.Document document = html_parser.parse(subjectPageText);
    final Map<String, String> result = <String, String>{};

    for (final dom.Element popup in document.querySelectorAll(
      'div.prg_popup[id^="prginfo_"]',
    )) {
      final String idAttr = popup.id.trim();
      final RegExpMatch? idMatch = RegExp(
        r'^prginfo_(\d+)$',
      ).firstMatch(idAttr);
      if (idMatch == null) {
        continue;
      }
      final String epId = idMatch.group(1) ?? '';
      if (epId.isEmpty) {
        continue;
      }

      final dom.Element? tipNode = popup.querySelector('span.tip');
      if (tipNode == null) {
        continue;
      }

      final String html = tipNode.innerHtml;
      final RegExpMatch? cnMatch = RegExp(
        r'中文标题\s*[:：]\s*([^<\r\n]+)',
        caseSensitive: false,
      ).firstMatch(html);
      if (cnMatch == null) {
        continue;
      }

      final String title = (cnMatch.group(1) ?? '').trim();
      if (title.isNotEmpty && !result.containsKey(epId)) {
        result[epId] = title;
      }
    }

    return result;
  }

  EpisodeProgress parseEpisodeProgress(
    String epPageText, {
    Map<String, int>? discussionByEpId,
  }) {
    final dom.Document document = html_parser.parse(epPageText);
    final List<dom.Element> rows = document.querySelectorAll(
      'li.line_odd, li.line_even',
    );

    int totalNumericEps = 0;
    int airedNumericEps = 0;
    int? latestAiredEp;
    String? latestAiredEpId;
    String? latestAiredOriginTitle;
    int? nextUnairedEp;
    final List<int> numericEpisodesInOrder = <int>[];
    final List<String> episodeIdsInOrder = <String>[];
    final List<String> episodeOriginTitlesInOrder = <String>[];

    for (final dom.Element row in rows) {
      final dom.Element? link = row.querySelector('h6 a[href^="/ep/"]');
      if (link == null) {
        continue;
      }

      final String linkText = link.text.trim();
      final RegExpMatch? match = RegExp(r'^(\d+)\.').firstMatch(linkText);
      if (match == null) {
        continue;
      }

      final RegExpMatch? titleMatch = RegExp(
        r'^\d+\.\s*(.+)$',
      ).firstMatch(linkText);
      final String originTitle = (titleMatch?.group(1) ?? '').trim();

      final int? epNo = int.tryParse(match.group(1)!);
      if (epNo == null) {
        continue;
      }

      final String epHref = link.attributes['href']?.trim() ?? '';
      final RegExpMatch? epIdMatch = RegExp(r'^/ep/(\d+)').firstMatch(epHref);
      final String epId = epIdMatch?.group(1) ?? '';

      totalNumericEps += 1;
      numericEpisodesInOrder.add(epNo);
      episodeIdsInOrder.add(epId);
      episodeOriginTitlesInOrder.add(originTitle);

      final dom.Element? statusNode = row.querySelector(
        'span.epAirStatus span',
      );
      final String classes = statusNode?.className ?? '';
      final bool isAired = classes.split(' ').contains('Air');

      if (isAired) {
        airedNumericEps += 1;
        if (latestAiredEp == null || epNo > latestAiredEp) {
          latestAiredEp = epNo;
          latestAiredEpId = epId.isEmpty ? latestAiredEpId : epId;
          latestAiredOriginTitle = originTitle.isEmpty
              ? latestAiredOriginTitle
              : originTitle;
        }
      }
    }

    for (final int epNo in numericEpisodesInOrder) {
      if (latestAiredEp == null || epNo > latestAiredEp) {
        nextUnairedEp = epNo;
        break;
      }
    }

    return EpisodeProgress(
      totalEpsListed: totalNumericEps,
      airedEps: airedNumericEps,
      latestAiredEp: latestAiredEp,
      latestAiredEpId: latestAiredEpId,
      latestAiredOriginTitle: latestAiredOriginTitle,
      nextEp: nextUnairedEp,
    );
  }
}

/// BangumiHomePage：组件或数据结构定义。
class BangumiHomePage extends StatefulWidget {
  const BangumiHomePage({
    super.key,
    this.autoBootstrap = true,
    this.initialThemeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final bool autoBootstrap;
  final ThemeMode initialThemeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<BangumiHomePage> createState() => _BangumiHomePageState();
}

/// _BangumiHomePageState：组件或数据结构定义。
class _BangumiHomePageState extends State<BangumiHomePage>
  with WidgetsBindingObserver {
  static const String _appBarLogoAsset = 'assets/images/logoWHT.svg';
  static const BoxFit _appBarBackgroundImageFit = BoxFit.cover;
  static const double _appBarLogoWidth = 140;
  static const double _appBarLogoHeight = _appBarLogoWidth;
  static const double _appBarLogoOpacity = 0.5;
  static const double _appBarLogoOffsetX = -10;
  static const double _appBarLogoOffsetY = 70;
  static const double _appBarLogoGapAboveTabBar = 2;
  static const Alignment _appBarLogoAlignment = Alignment.centerLeft;
  static const EdgeInsets _appBarLogoPadding = EdgeInsets.only(left: 0);

  // 在这里手动调整柱状图组件位置与尺寸。
  static const EpisodeCommentChartLayout _commentChartLayout =
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

  final BangumiService _service = BangumiService();
  final CoverCacheManager _coverCacheManager = CoverCacheManager();
  final CalendarCacheManager _calendarCacheManager = CalendarCacheManager();
  final AppStateStore _appStateStore = AppStateStore();
  final WatchArchiveStore _watchArchiveStore = WatchArchiveStore();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoadingSchedule = true;
  bool _isLoadingProgress = false;
  bool _isCachingCalendarCovers = false;
  int _calendarCoverCacheDone = 0;
  int _calendarCoverCacheTotal = 0;
  int _progressRefreshDone = 0;
  int _progressRefreshTotal = 0;
  String _statusText = '就绪';
  bool _showStatusText = false;
  Timer? _statusTextTimer;
  bool _showNetworkIndicator = false;
  Timer? _networkIndicatorHideTimer;
  List<BgmListOnAirEntry> _bgmOnAirEntries = <BgmListOnAirEntry>[];
  List<BgmListScheduleCandidate> _bgmScheduleCandidates =
      <BgmListScheduleCandidate>[];
  final Map<String, int?> _subjectTotalEpisodesCache = <String, int?>{};
  String _scheduleError = '';
  final List<String> _debugLogs = <String>[];
  int _lastLoggedActiveRequests = -1;
  int _settingProgressConcurrency = defaultSettingProgressConcurrency;
  int _settingCoverCacheConcurrency = defaultSettingCoverCacheConcurrency;
  String _settingApiUserAgent = appUserAgent;
  ThemeMode _settingThemeMode = ThemeMode.system;
  bool _settingAppBarBackgroundImageEnabled = false;
  String _settingAppBarBackgroundImagePath = '';
  bool _settingTimezoneConversionEnabled =
      defaultSettingTimezoneConversionEnabled;
  int _settingTimezoneOffsetMinutes = defaultSettingTimezoneOffsetMinutes;
  bool _weekCalendarShowAll = false;
  bool _debugShowChartHoverHitArea = false;
  String? _hoveredChartSubjectId;
  int? _hoveredChartBarIndex;
  int? _debugHoverLocalX;
  int? _debugHoverLocalY;
  int? _debugHoverBarCount;

  static const int _maxDebugLogEntries = 400;

  List<DaySchedule> _scheduleData = <DaySchedule>[];
  List<SubjectItem> _allItems = <SubjectItem>[];
  List<SubjectItem> _todayItems = <SubjectItem>[];
  List<SubjectItem> _watchlist = <SubjectItem>[];
  final Map<String, SubjectProgress> _progressCache =
      <String, SubjectProgress>{};
    final Map<String, SubjectProgress> _rawProgressCache =
      <String, SubjectProgress>{};
    final Map<String, int> _legacyAbsoluteProgressCorrections =
      <String, int>{};
    bool _progressCorrectionMigrationDirty = false;
  Map<String, int> _manualProgressCorrections = <String, int>{};
  Set<String> _selectedIds = <String>{};
  int? _debugWeekdayOverride;

  String get _systemWeekday {
    final DateTime now =
        DateTime.now().toUtc().add(Duration(minutes: _effectiveDisplayTimezoneOffsetMinutes));
    return weekdayMap[now.weekday] ?? '未知';
  }

  String get _effectiveTodayWeekday {
    if (_debugWeekdayOverride != null) {
      return weekdayMap[_debugWeekdayOverride!] ?? _systemWeekday;
    }
    return _systemWeekday;
  }

  @override
  /// 初始化状态、监听与启动流程。
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetHardwareKeyboardState('初始化');
    _settingThemeMode = widget.initialThemeMode;
    _appendDebugLog('应用启动');
    _service.onNetworkLog = _appendDebugLog;
    _service.activeRequests.addListener(_onNetworkActivityChanged);
    _onNetworkActivityChanged();
    if (widget.autoBootstrap) {
      _bootstrap();
    }
  }

  @override
  /// 处理父组件参数更新后的状态同步。
  void didUpdateWidget(covariant BangumiHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialThemeMode != widget.initialThemeMode &&
        _settingThemeMode != widget.initialThemeMode) {
      _settingThemeMode = widget.initialThemeMode;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resetHardwareKeyboardState('恢复前台');
    }
  }

  @override
  /// 释放控制器、计时器与监听资源。
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.onNetworkLog = null;
    _service.activeRequests.removeListener(_onNetworkActivityChanged);
    _service.dispose();
    _networkIndicatorHideTimer?.cancel();
    _statusTextTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _resetHardwareKeyboardState(String reason) {
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      HardwareKeyboard.instance.clearState();
      _appendDebugLog('键盘状态已重置($reason)');
    } catch (_) {
      // Ignore if current backend does not support keyboard state reset.
    }
  }

  
  void _onNetworkActivityChanged() {
    final int activeCount = _service.activeRequests.value;
    if (_lastLoggedActiveRequests != activeCount) {
      if (activeCount > 0 && _lastLoggedActiveRequests <= 0) {
        _appendDebugLog('网络请求开始（active=$activeCount）');
      } else if (activeCount == 0 && _lastLoggedActiveRequests > 0) {
        _appendDebugLog('网络请求空闲');
      }
      _lastLoggedActiveRequests = activeCount;
    }

    if (activeCount > 0) {
      _networkIndicatorHideTimer?.cancel();
      if (!_showNetworkIndicator && mounted) {
        setState(() {
          _showNetworkIndicator = true;
        });
      }
      return;
    }

    _networkIndicatorHideTimer?.cancel();
    _networkIndicatorHideTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      if (_service.activeRequests.value == 0 && _showNetworkIndicator) {
        setState(() {
          _showNetworkIndicator = false;
        });
      }
    });
  }

  void _showStatus(
    String message, {
    bool autoHide = true,
    Duration hideDelay = const Duration(seconds: 4),
  }) {
    _appendDebugLog('状态: $message');
    _statusTextTimer?.cancel();
    if (!mounted) {
      return;
    }

    setState(() {
      _statusText = message;
      _showStatusText = true;
    });

    if (!autoHide) {
      return;
    }

    _statusTextTimer = Timer(hideDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showStatusText = false;
      });
    });
  }

  
  String _debugTimestamp() {
    final DateTime now = DateTime.now();
    final String hh = now.hour.toString().padLeft(2, '0');
    final String mm = now.minute.toString().padLeft(2, '0');
    final String ss = now.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  
  void _appendDebugLog(String message) {
    _debugLogs.add('[${_debugTimestamp()}] $message');
    if (_debugLogs.length > _maxDebugLogEntries) {
      _debugLogs.removeRange(0, _debugLogs.length - _maxDebugLogEntries);
    }
  }

  Future<void> _bootstrap() async {
    _appendDebugLog('开始初始化');
    await _loadSettings();
    await _loadProgressCorrections();
    final bool cacheDirMissingAtStartup = await _coverCacheManager
        .isCacheDirMissingInAppDir();
    if (cacheDirMissingAtStartup) {
      _appendDebugLog('检测到软件目录缺少 cover_cache，将在启动后触发封面缓存');
    }

    await _loadWatchlist();
    await _refreshCalendarSchedule(initial: true);

    if (cacheDirMissingAtStartup && _scheduleData.isNotEmpty) {
      _showStatus('检测到封面缓存目录缺失，正在初始化封面缓存...', autoHide: false);
      unawaited(_cacheAllCalendarCovers(_scheduleData));
    }

    await _refreshProgressFromMainAction();
    _appendDebugLog('初始化完成');
  }

  Future<void> _refreshProgressFromMainAction() async {
    await _refreshProgress();
  }

  Future<void> _refreshCalendarFromMainAction() async {
    await _refreshCalendarSchedule(forceNetwork: true);
    if (!mounted) {
      return;
    }
    await _refreshProgressFromMainAction();
  }

  
  int _clampProgressConcurrency(int value) {
    return value.clamp(1, 30);
  }

  
  int _clampCoverCacheConcurrency(int value) {
    return value.clamp(1, 24);
  }

  
  int _clampTimezoneOffsetMinutes(int value) {
    return BroadcastTimeConverter.normalizeTimezoneOffsetMinutes(value);
  }

  int get _effectiveDisplayTimezoneOffsetMinutes =>
      _settingTimezoneConversionEnabled
      ? _settingTimezoneOffsetMinutes
      : BroadcastTimeConverter.jstOffsetMinutes;

  String get _currentTimezoneFullLabel =>
      _settingTimezoneConversionEnabled
      ? BroadcastTimeConverter.formatUtcOffsetLabel(_settingTimezoneOffsetMinutes)
      : 'JST (${BroadcastTimeConverter.formatUtcOffsetLabel(BroadcastTimeConverter.jstOffsetMinutes)})';

  
  String _calendarCacheTimezoneToken() {
    return '${_settingTimezoneConversionEnabled ? 1 : 0}:$_effectiveDisplayTimezoneOffsetMinutes';
  }

  Future<String> _loadCalendarCacheTimezoneToken() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    return (state[calendarCacheTimezoneTokenKey] ?? '').toString().trim();
  }

  Future<void> _saveCalendarCacheTimezoneToken() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    state[calendarCacheTimezoneTokenKey] = _calendarCacheTimezoneToken();
    await _appStateStore.writeState(state);
  }

  Future<bool> _isCalendarCacheTimezoneMatched() async {
    final String savedToken = await _loadCalendarCacheTimezoneToken();
    final String currentToken = _calendarCacheTimezoneToken();
    return savedToken.isNotEmpty && savedToken == currentToken;
  }

  List<DaySchedule> _convertScheduleFromJstForDisplay(
    List<DaySchedule> source,
  ) {
    if (!_settingTimezoneConversionEnabled) {
      return source;
    }

    final int targetOffset = _settingTimezoneOffsetMinutes;
    final List<String> orderedWeekdays = <String>[
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日',
    ];
    final Map<String, List<SubjectItem>> grouped = <String, List<SubjectItem>>{
      for (final String day in orderedWeekdays) day: <SubjectItem>[],
    };

    for (final DaySchedule day in source) {
      grouped.putIfAbsent(day.weekday, () => <SubjectItem>[]);
      for (final SubjectItem item in day.items) {
        String weekday = day.weekday;
        String time = item.updateTime;
        if (day.weekday.trim().isNotEmpty && item.updateTime.trim().isNotEmpty) {
          final ConvertedWeekdayTime? converted =
              BroadcastTimeConverter.convertWeekdayAndTime(
                weekday: day.weekday,
                time: item.updateTime,
                fromOffsetMinutes: BroadcastTimeConverter.jstOffsetMinutes,
                toOffsetMinutes: targetOffset,
              );
          if (converted != null) {
            weekday = converted.weekday;
            time = converted.time;
          }
        }

        grouped.putIfAbsent(weekday, () => <SubjectItem>[]).add(
          item.copyWith(updateTime: time),
        );
      }
    }

    final List<DaySchedule> converted = <DaySchedule>[];
    for (final String day in orderedWeekdays) {
      converted.add(DaySchedule(weekday: day, items: grouped[day] ?? <SubjectItem>[]));
      grouped.remove(day);
    }
    grouped.forEach((String day, List<SubjectItem> items) {
      converted.add(DaySchedule(weekday: day, items: items));
    });
    return converted;
  }

  Future<void> _loadSettings() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    final String raw = jsonEncode(state[settingsStorageKey] ?? <String, dynamic>{});
    Map<String, dynamic> jsonMap = <String, dynamic>{};
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        jsonMap = decoded;
      }
    } catch (_) {
      jsonMap = <String, dynamic>{};
    }

    _settingProgressConcurrency = _clampProgressConcurrency(
      (jsonMap['progress_concurrency'] as num?)?.toInt() ??
          defaultSettingProgressConcurrency,
    );
    _settingCoverCacheConcurrency = _clampCoverCacheConcurrency(
      (jsonMap['cover_cache_concurrency'] as num?)?.toInt() ??
          defaultSettingCoverCacheConcurrency,
    );
    _settingApiUserAgent = (jsonMap['api_user_agent'] as String? ?? appUserAgent)
      .trim();
    _settingThemeMode = themeModeFromStorageValue(
      (jsonMap[themeModeSettingKey] as String? ?? ''),
    );
    _settingAppBarBackgroundImageEnabled =
      (jsonMap[appBarBackgroundImageEnabledSettingKey] as bool?) ?? false;
    _settingAppBarBackgroundImagePath =
      (jsonMap[appBarBackgroundImagePathSettingKey] as String? ?? '').trim();
    _settingTimezoneConversionEnabled =
        (jsonMap[timezoneConversionEnabledSettingKey] as bool?) ??
        defaultSettingTimezoneConversionEnabled;
    _settingTimezoneOffsetMinutes = _clampTimezoneOffsetMinutes(
      (jsonMap[timezoneOffsetMinutesSettingKey] as num?)?.toInt() ??
          defaultSettingTimezoneOffsetMinutes,
    );

    _service.apiUserAgent = _settingApiUserAgent.isEmpty
      ? appUserAgent
      : _settingApiUserAgent;
    widget.onThemeModeChanged?.call(_settingThemeMode);
    _appendDebugLog('网络: 当前 API UA: ${_service.effectiveApiUserAgent}');
    _appendDebugLog('时区: 当前显示时区 $_currentTimezoneFullLabel');
  }

  Future<void> _saveSettings() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    state[settingsStorageKey] = <String, dynamic>{
      'progress_concurrency': _settingProgressConcurrency,
      'cover_cache_concurrency': _settingCoverCacheConcurrency,
      'api_user_agent': _settingApiUserAgent,
      themeModeSettingKey: themeModeToStorageValue(_settingThemeMode),
      appBarBackgroundImageEnabledSettingKey:
          _settingAppBarBackgroundImageEnabled,
      appBarBackgroundImagePathSettingKey: _settingAppBarBackgroundImagePath,
      timezoneConversionEnabledSettingKey: _settingTimezoneConversionEnabled,
      timezoneOffsetMinutesSettingKey: _settingTimezoneOffsetMinutes,
    };
    await _appStateStore.writeState(state);
  }

  Future<void> _loadProgressCorrections() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    final String legacyRaw = jsonEncode(
      state[progressCorrectionStorageKey] ?? <String, dynamic>{},
    );
    final String deltaRaw = jsonEncode(
      state[progressCorrectionDeltaStorageKey] ?? <String, dynamic>{},
    );

    Map<String, int> legacy = <String, int>{};
    Map<String, int> delta = <String, int>{};
    try {
      final dynamic decodedLegacy = jsonDecode(legacyRaw);
      if (decodedLegacy is Map<String, dynamic>) {
        decodedLegacy.forEach((String key, dynamic value) {
          final int? parsed = (value as num?)?.toInt();
          if (key.isNotEmpty && parsed != null && parsed >= 0) {
            legacy[key] = parsed;
          }
        });
      }

      final dynamic decodedDelta = jsonDecode(deltaRaw);
      if (decodedDelta is Map<String, dynamic>) {
        decodedDelta.forEach((String key, dynamic value) {
          final int? parsed = (value as num?)?.toInt();
          if (key.isNotEmpty && parsed != null && parsed != 0) {
            delta[key] = parsed;
          }
        });
      }

      for (final String sid in delta.keys) {
        legacy.remove(sid);
      }
    } catch (_) {
      legacy = <String, int>{};
      delta = <String, int>{};
    }

    _legacyAbsoluteProgressCorrections
      ..clear()
      ..addAll(legacy);
    _manualProgressCorrections = delta;
    _progressCorrectionMigrationDirty = false;
  }

  Future<void> _saveProgressCorrections() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    final Map<String, int> sanitizedDelta = <String, int>{};
    _manualProgressCorrections.forEach((String key, int value) {
      if (key.isNotEmpty && value != 0) {
        sanitizedDelta[key] = value;
      }
    });

    state[progressCorrectionStorageKey] = _legacyAbsoluteProgressCorrections;
    state[progressCorrectionDeltaStorageKey] = sanitizedDelta;
    await _appStateStore.writeState(state);
    _manualProgressCorrections = sanitizedDelta;
    _progressCorrectionMigrationDirty = false;
  }

  
  int _resolveTheoreticalAiredEp(SubjectProgress progress) {
    return math.max(0, progress.latestAiredEp ?? progress.airedEps ?? 0);
  }

  
  int _clampCorrectedEp(int value, int? totalEps) {
    if (totalEps == null) {
      return math.max(0, value);
    }
    return value.clamp(0, totalEps).toInt();
  }

  void _migrateLegacyCorrectionToDelta(
    String subjectId,
    SubjectProgress progress,
  ) {
    final int? legacyAbsolute = _legacyAbsoluteProgressCorrections[subjectId];
    if (legacyAbsolute == null) {
      return;
    }

    final int theoretical = _resolveTheoreticalAiredEp(progress);
    final int delta = legacyAbsolute - theoretical;
    _legacyAbsoluteProgressCorrections.remove(subjectId);
    if (delta == 0) {
      _manualProgressCorrections.remove(subjectId);
    } else {
      _manualProgressCorrections[subjectId] = delta;
    }
    _progressCorrectionMigrationDirty = true;
  }

  SubjectProgress _applyAbsoluteCorrection(
    SubjectProgress progress,
    int absoluteEp,
  ) {
    final int? totalEps = progress.totalEpsDeclared ?? progress.totalEpsListed;
    final int corrected = _clampCorrectedEp(absoluteEp, totalEps);
    final int? nextEp = totalEps != null && corrected < totalEps
        ? corrected + 1
        : null;
    final int theoretical = _resolveTheoreticalAiredEp(progress);
    final String? correctedEpTitle = corrected <= 0
        ? null
        : (progress.episodeTitleByEp[corrected]?.trim().isNotEmpty ?? false)
        ? progress.episodeTitleByEp[corrected]
        : (theoretical == corrected ? progress.latestAiredCnTitle : null);

    return SubjectProgress(
      totalEpsDeclared: progress.totalEpsDeclared,
      totalEpsListed: progress.totalEpsListed,
      airedEps: corrected,
      latestAiredEp: corrected > 0 ? corrected : null,
      latestAiredCnTitle: correctedEpTitle,
      latestAiredAtLabel: theoretical == corrected
          ? progress.latestAiredAtLabel
          : null,
      nextEp: nextEp,
      ratingScore: progress.ratingScore,
      episodeCommentCounts: progress.episodeCommentCounts,
      episodeTitleByEp: progress.episodeTitleByEp,
      progressText: totalEps == null ? '$corrected/未知' : '$corrected/$totalEps',
    );
  }

  SubjectProgress _applyDeltaCorrection(
    SubjectProgress progress,
    int delta,
  ) {
    final int? totalEps = progress.totalEpsDeclared ?? progress.totalEpsListed;
    final int theoretical = _resolveTheoreticalAiredEp(progress);
    final int corrected = _clampCorrectedEp(theoretical + delta, totalEps);
    final int? nextEp = totalEps != null && corrected < totalEps
        ? corrected + 1
        : null;
    final String? correctedEpTitle = corrected <= 0
        ? null
        : (progress.episodeTitleByEp[corrected]?.trim().isNotEmpty ?? false)
        ? progress.episodeTitleByEp[corrected]
        : (theoretical == corrected ? progress.latestAiredCnTitle : null);

    return SubjectProgress(
      totalEpsDeclared: progress.totalEpsDeclared,
      totalEpsListed: progress.totalEpsListed,
      airedEps: corrected,
      latestAiredEp: corrected > 0 ? corrected : null,
      latestAiredCnTitle: correctedEpTitle,
      latestAiredAtLabel: theoretical == corrected
          ? progress.latestAiredAtLabel
          : null,
      nextEp: nextEp,
      ratingScore: progress.ratingScore,
      episodeCommentCounts: progress.episodeCommentCounts,
      episodeTitleByEp: progress.episodeTitleByEp,
      progressText: totalEps == null ? '$corrected/未知' : '$corrected/$totalEps',
    );
  }

  SubjectProgress _applyManualProgressCorrection(
    String subjectId,
    SubjectProgress progress,
  ) {
    if (progress.error != null && progress.error!.isNotEmpty) {
      return progress;
    }

    final int? manualDelta = _manualProgressCorrections[subjectId];
    if (manualDelta != null) {
      return _applyDeltaCorrection(progress, manualDelta);
    }

    final int? legacyAbsolute = _legacyAbsoluteProgressCorrections[subjectId];
    if (legacyAbsolute != null) {
      final SubjectProgress corrected = _applyAbsoluteCorrection(
        progress,
        legacyAbsolute,
      );
      _migrateLegacyCorrectionToDelta(subjectId, progress);
      return corrected;
    }

    return progress;
  }

  Future<void> _openSettingsDialog() async {
    int tempProgressConcurrency = _settingProgressConcurrency;
    int tempCoverCacheConcurrency = _settingCoverCacheConcurrency;
    String tempApiUserAgent = _settingApiUserAgent;
    ThemeMode tempThemeMode = _settingThemeMode;
    bool tempAppBarBackgroundImageEnabled =
      _settingAppBarBackgroundImageEnabled;
    String tempAppBarBackgroundImagePath = _settingAppBarBackgroundImagePath;
    bool tempTimezoneConversionEnabled = _settingTimezoneConversionEnabled;
    int tempTimezoneOffsetMinutes = _settingTimezoneOffsetMinutes;
    final ThemeMode previousThemeMode = _settingThemeMode;
    final bool previousTimezoneConversionEnabled =
        _settingTimezoneConversionEnabled;
    final int previousTimezoneOffsetMinutes = _settingTimezoneOffsetMinutes;
    final List<int> commonTimezoneOffsets = <int>[
      for (int hour = -12; hour <= 14; hour++) hour * 60,
    ];

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('设置'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DropdownButtonFormField<ThemeMode>(
                        initialValue: tempThemeMode,
                        decoration: const InputDecoration(
                          labelText: '主题模式',
                          border: OutlineInputBorder(),
                        ),
                        items: const <ThemeMode>[
                          ThemeMode.system,
                          ThemeMode.light,
                          ThemeMode.dark,
                        ].map((ThemeMode mode) {
                          return DropdownMenuItem<ThemeMode>(
                            value: mode,
                            child: Text(themeModeDisplayText(mode)),
                          );
                        }).toList(),
                        onChanged: (ThemeMode? value) {
                          if (value == null) {
                            return;
                          }
                          setLocalState(() {
                            tempThemeMode = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: tempAppBarBackgroundImageEnabled,
                        onChanged: (bool value) {
                          setLocalState(() {
                            tempAppBarBackgroundImageEnabled = value;
                          });
                        },
                        title: const Text('启用 AppBar 背景图'),
                        subtitle: const Text(
                          '可填本地路径或 http(s) 地址',
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue: tempAppBarBackgroundImagePath,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'AppBar/TabBar 背景图路径',
                          hintText:
                              '例如 assets/images/appbar_bg.png 或 C:/path/bg.png',
                        ),
                        onChanged: (String value) {
                          setLocalState(() {
                            tempAppBarBackgroundImagePath = value.trim();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('进度刷新并发: $tempProgressConcurrency'),
                      ),
                      Slider(
                        min: 1,
                        max: 30,
                        divisions: 29,
                        value: tempProgressConcurrency.toDouble(),
                        label: '$tempProgressConcurrency',
                        onChanged: (double value) {
                          setLocalState(() {
                            tempProgressConcurrency = _clampProgressConcurrency(
                              value.round(),
                            );
                          });
                        },
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('封面缓存并发: $tempCoverCacheConcurrency'),
                      ),
                      Slider(
                        min: 1,
                        max: 24,
                        divisions: 23,
                        value: tempCoverCacheConcurrency.toDouble(),
                        label: '$tempCoverCacheConcurrency',
                        onChanged: (double value) {
                          setLocalState(() {
                            tempCoverCacheConcurrency =
                                _clampCoverCacheConcurrency(value.round());
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: tempTimezoneConversionEnabled,
                        onChanged: (bool value) {
                          setLocalState(() {
                            tempTimezoneConversionEnabled = value;
                          });
                        },
                        title: const Text('转换时区'),
                        subtitle: Text(
                          tempTimezoneConversionEnabled
                              ? '已开启，当前目标 ${BroadcastTimeConverter.formatUtcOffsetLabel(tempTimezoneOffsetMinutes)}'
                              : '已关闭，按 JST 显示',
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        initialValue: tempTimezoneOffsetMinutes,
                        decoration: const InputDecoration(
                          labelText: '目标时区（固定选项）',
                          border: OutlineInputBorder(),
                        ),
                        items: commonTimezoneOffsets
                            .map(
                              (int offset) => DropdownMenuItem<int>(
                                value: offset,
                                child: Text(
                                  BroadcastTimeConverter.formatUtcOffsetLabel(
                                    offset,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: tempTimezoneConversionEnabled
                            ? (int? value) {
                                if (value == null) {
                                  return;
                                }
                                setLocalState(() {
                                  tempTimezoneOffsetMinutes =
                                      _clampTimezoneOffsetMinutes(value);
                                });
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Bangumi API UA'),
                      ),
                      const SizedBox(height: 5),
                      TextFormField(
                        initialValue: tempApiUserAgent,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '用于 Bangumi API 请求的 User-Agent',
                        ),
                        onChanged: (String value) {
                          setLocalState(() {
                            tempApiUserAgent = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton.icon(
                  onPressed: () async {
                    await _openWatchArchiveDialog();
                  },
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('关注归档'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop(false);
                    await _clearCoverCache();
                  },
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('清除封面缓存'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final bool themeModeChanged = previousThemeMode != tempThemeMode;
    final bool timezoneChanged =
        previousTimezoneConversionEnabled != tempTimezoneConversionEnabled ||
        previousTimezoneOffsetMinutes != tempTimezoneOffsetMinutes;

    setState(() {
      _settingProgressConcurrency = tempProgressConcurrency;
      _settingCoverCacheConcurrency = tempCoverCacheConcurrency;
      _settingApiUserAgent = tempApiUserAgent.trim();
      _settingThemeMode = tempThemeMode;
      _settingAppBarBackgroundImageEnabled = tempAppBarBackgroundImageEnabled;
      _settingAppBarBackgroundImagePath = tempAppBarBackgroundImagePath.trim();
      _settingTimezoneConversionEnabled = tempTimezoneConversionEnabled;
      _settingTimezoneOffsetMinutes = _clampTimezoneOffsetMinutes(
        tempTimezoneOffsetMinutes,
      );
      _service.apiUserAgent = _settingApiUserAgent.isEmpty
          ? appUserAgent
          : _settingApiUserAgent;
    });
    if (themeModeChanged) {
      widget.onThemeModeChanged?.call(_settingThemeMode);
      _appendDebugLog('主题: 当前模式 ${themeModeDisplayText(_settingThemeMode)}');
    }
    await _saveSettings();
    _appendDebugLog('网络: 当前 API UA: ${_service.effectiveApiUserAgent}');
    _appendDebugLog('时区: 当前显示时区 $_currentTimezoneFullLabel');

    if (timezoneChanged) {
      _showStatus('设置已保存，正在按新时区重算日历与进度...', autoHide: false);
      await _refreshCalendarSchedule(forceNetwork: true);
      await _refreshProgressFromMainAction();
      _showStatus('设置已保存并完成时区重算');
      return;
    }

    _showStatus('设置已保存');
  }

  Future<void> _openWatchArchiveDialog() async {
    final List<WatchArchiveEntry> entries = await _watchArchiveStore.load();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('关注归档'),
          content: SizedBox(
            width: 560,
            height: 420,
            child: entries.isEmpty
                ? const Center(child: Text('暂无归档记录'))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (
                      BuildContext context,
                      int index,
                    ) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final WatchArchiveEntry entry =
                          entries[entries.length - 1 - index];
                      return ListTile(
                        dense: true,
                        title: Text(entry.text),
                        subtitle: Text('归档时间: ${entry.archivedAt}'),
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadWatchlist() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    final String raw = jsonEncode(state[watchlistStorageKey] ?? <dynamic>[]);
    List<dynamic> parsed;
    try {
      parsed = jsonDecode(raw) as List<dynamic>;
    } catch (e) {
      _appendDebugLog('解析关注列表失败: $e');
      parsed = <dynamic>[];
    }

    final List<SubjectItem> items = parsed
        .whereType<Map<String, dynamic>>()
        .map(SubjectItem.fromJson)
        .toList();
    setState(() {
      _watchlist = items;
      _selectedIds = _watchlist.map((SubjectItem e) => e.subjectId).toSet();
    });

    unawaited(_hydrateCachedCoversForWatchlistItems());
  }

  Future<void> _saveWatchlist() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    state[watchlistStorageKey] = _watchlist
        .map((SubjectItem e) => e.toJson())
        .toList();
    await _appStateStore.writeState(state);
  }

  Future<bool> _shouldAutoRefreshOnMonthFirst() async {
    final DateTime now = DateTime.now();
    if (now.day != 1) {
      return false;
    }

    final String monthToken =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final Map<String, dynamic> state = await _appStateStore.readState();
    final String savedMonth =
        (state[calendarAutoRefreshMonthKey] ?? '').toString();
    return savedMonth != monthToken;
  }

  Future<void> _markAutoRefreshDoneForCurrentMonth() async {
    final DateTime now = DateTime.now();
    final String monthToken =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final Map<String, dynamic> state = await _appStateStore.readState();
    state[calendarAutoRefreshMonthKey] = monthToken;
    await _appStateStore.writeState(state);
  }

  
  String _currentQuarterLabel() {
    final DateTime now = DateTime.now();
    final int quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    return '${now.year}年$quarterStartMonth月';
  }

  Future<void> _archiveMissingWatchlistItemsAfterCalendar(
    List<DaySchedule> schedule,
  ) async {
    if (_watchlist.isEmpty) {
      return;
    }

    final Set<String> currentCalendarIds = schedule
        .expand((DaySchedule day) => day.items)
        .map((SubjectItem item) => item.subjectId)
        .where((String id) => id.isNotEmpty)
        .toSet();

    // Guard against accidental mass-removal if fetched schedule is unexpectedly empty.
    if (currentCalendarIds.isEmpty) {
      return;
    }

    final List<SubjectItem> toArchive = _watchlist
        .where(
          (SubjectItem item) =>
              item.subjectId.isNotEmpty &&
              !currentCalendarIds.contains(item.subjectId),
        )
        .toList();

    if (toArchive.isEmpty) {
      return;
    }

    final String quarter = _currentQuarterLabel();
    final List<WatchArchiveEntry> entries = toArchive
        .map(
          (SubjectItem item) =>
              WatchArchiveEntry.fromSubject(item, quarter: quarter),
        )
        .toList();
    await _watchArchiveStore.appendEntries(entries);

    final Set<String> removedIds = toArchive
        .map((SubjectItem item) => item.subjectId)
        .toSet();

    if (!mounted) {
      return;
    }

    setState(() {
      _watchlist = _watchlist
          .where((SubjectItem item) => !removedIds.contains(item.subjectId))
          .toList();
      _selectedIds.removeWhere((String id) => removedIds.contains(id));
      _manualProgressCorrections.removeWhere(
        (String id, int _) => removedIds.contains(id),
      );
      _legacyAbsoluteProgressCorrections.removeWhere(
        (String id, int _) => removedIds.contains(id),
      );
      for (final String id in removedIds) {
        _progressCache.remove(id);
        _rawProgressCache.remove(id);
      }
    });

    await _saveWatchlist();
    await _saveProgressCorrections();
    _showStatus('已归档并移除 ${toArchive.length} 部未出现在当前日历的关注番剧');
  }

  void _applyScheduleData(
    List<DaySchedule> schedule, {
    required String doneStatusText,
  }) {
    final Map<String, SubjectItem> merged = <String, SubjectItem>{};
    for (final DaySchedule day in schedule) {
      for (final SubjectItem item in day.items) {
        if (item.subjectId.isNotEmpty && !merged.containsKey(item.subjectId)) {
          merged[item.subjectId] = item;
        }
      }
    }
    final List<SubjectItem> allItems = merged.values.toList();
    final List<SubjectItem> todayItems = _resolveTodayItemsFromSchedule(
      schedule,
    );
    final Map<String, SubjectItem> latestById = <String, SubjectItem>{
      for (final SubjectItem item in allItems)
        if (item.subjectId.isNotEmpty) item.subjectId: item,
    };

    setState(() {
      _scheduleData = schedule;
      _allItems = allItems;
      _todayItems = todayItems;
      _watchlist = _watchlist.map((SubjectItem item) {
        final SubjectItem? latest = latestById[item.subjectId];
        if (latest == null) {
          return item;
        }
        return item.copyWith(
          subjectUrl: latest.subjectUrl,
          nameCn: latest.nameCn,
          nameOrigin: latest.nameOrigin,
          coverUrl: latest.coverUrl,
          updateTime: latest.updateTime,
        );
      }).toList();

      final Set<String> validSelected = _selectedIds
          .where(
            (String id) =>
                allItems.any((SubjectItem item) => item.subjectId == id),
          )
          .toSet();
      _selectedIds = validSelected;

      _isLoadingSchedule = false;
    });

    unawaited(_hydrateCachedCoversForWatchlistItems());
    unawaited(_hydrateCachedCoversForScheduleItems());
    _showStatus(doneStatusText);
  }

  Future<void> _ensureBgmListScheduleCandidatesLoaded({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _bgmScheduleCandidates.isNotEmpty) {
      return;
    }
    if (forceRefresh) {
      _appendDebugLog('日历: 强制重新抓取 BGMLIST 全部番组 JSON');
    }

    final String onAirJson = await _service.fetchBgmListOnAirJson();
    if (onAirJson.trim().isEmpty) {
      _bgmScheduleCandidates = <BgmListScheduleCandidate>[];
      return;
    }

    final List<BgmListScheduleCandidate> parsed =
        _service.parseBgmListScheduleCandidates(onAirJson);
    _bgmScheduleCandidates = parsed;
    _appendDebugLog('日历: BGMLIST 候选条目 ${parsed.length} 条');
  }

  Future<int?> _loadSubjectTotalEpisodesCached(String subjectId) async {
    if (subjectId.isEmpty) {
      return null;
    }
    if (_subjectTotalEpisodesCache.containsKey(subjectId)) {
      return _subjectTotalEpisodesCache[subjectId];
    }

    try {
      final int? total = await _service.fetchSubjectTotalEpisodes(subjectId);
      _subjectTotalEpisodesCache[subjectId] = total;
      return total;
    } catch (e) {
      _appendDebugLog('日历: 获取总集数失败 subject=$subjectId ($e)');
      _subjectTotalEpisodesCache[subjectId] = null;
      return null;
    }
  }

  Future<bool> _isCurrentSeasonCandidate(
    BgmListScheduleCandidate candidate,
    DateTime nowJst,
  ) async {
    final int? totalEpisodes = await _loadSubjectTotalEpisodesCached(
      candidate.subjectId,
    );
    if (totalEpisodes == null || totalEpisodes <= 0) {
      _appendDebugLog('日历: 跳过 ${candidate.subjectId}，Bangumi API 总集数缺失');
      return false;
    }

    final int spanDays = candidate.periodDays * math.max(0, totalEpisodes - 1);
    final DateTime estimatedEnd = candidate.beginJst.add(
      Duration(days: spanDays),
    );
    return !nowJst.isBefore(candidate.beginJst) && !nowJst.isAfter(estimatedEnd);
  }

  Future<List<BgmListScheduleCandidate>> _resolveCurrentSeasonCandidates(
    List<BgmListScheduleCandidate> source,
  ) async {
    if (source.isEmpty) {
      return <BgmListScheduleCandidate>[];
    }

    final DateTime nowJst = DateTime.now().toUtc().add(
      const Duration(hours: 9),
    );
    final Map<String, BgmListScheduleCandidate> uniqueById =
        <String, BgmListScheduleCandidate>{};
    for (final BgmListScheduleCandidate item in source) {
      uniqueById.putIfAbsent(item.subjectId, () => item);
    }
    final List<BgmListScheduleCandidate> candidates = uniqueById.values
        .where((BgmListScheduleCandidate item) =>
            !item.beginJst.isAfter(nowJst) &&
            item.periodDays > 0 &&
            item.weekdayJst.trim().isNotEmpty &&
            item.updateTimeJst.trim().isNotEmpty)
        .toList();

    if (candidates.isEmpty) {
      return <BgmListScheduleCandidate>[];
    }

    final List<BgmListScheduleCandidate> included = <BgmListScheduleCandidate>[];
    final int concurrency = math.max(
      1,
      math.min(_settingProgressConcurrency, 12),
    );
    int nextIndex = 0;

    int? takeNextIndex() {
      if (nextIndex >= candidates.length) {
        return null;
      }
      final int current = nextIndex;
      nextIndex += 1;
      return current;
    }

    Future<void> worker() async {
      while (true) {
        final int? i = takeNextIndex();
        if (i == null) {
          return;
        }

        final BgmListScheduleCandidate candidate = candidates[i];
        final bool include = await _isCurrentSeasonCandidate(candidate, nowJst);
        if (include) {
          included.add(candidate);
        }
      }
    }

    final int workerCount = math.min(concurrency, candidates.length);
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    return included;
  }

  List<DaySchedule> _buildScheduleFromCandidates(
    List<BgmListScheduleCandidate> candidates,
  ) {
    const List<String> orderedWeekdays = <String>[
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日',
    ];
    final Map<String, List<SubjectItem>> grouped = <String, List<SubjectItem>>{
      for (final String day in orderedWeekdays) day: <SubjectItem>[],
    };

    for (final BgmListScheduleCandidate candidate in candidates) {
      if (!grouped.containsKey(candidate.weekdayJst)) {
        continue;
      }

      grouped[candidate.weekdayJst]!.add(
        SubjectItem(
          subjectId: candidate.subjectId,
          subjectUrl: candidate.subjectUrl,
          nameCn: candidate.titleCn,
          nameOrigin: candidate.titleJp,
          coverUrl: candidate.coverUrl,
          updateTime: candidate.updateTimeJst,
        ),
      );
    }

    final List<DaySchedule> schedule = <DaySchedule>[];
    for (final String weekday in orderedWeekdays) {
      final List<SubjectItem> items = grouped[weekday] ?? <SubjectItem>[];
      if (items.isEmpty) {
        continue;
      }
      items.sort((SubjectItem a, SubjectItem b) {
        final int timeCompare = _parseUpdateTimeMinutes(
          a.updateTime,
        ).compareTo(_parseUpdateTimeMinutes(b.updateTime));
        if (timeCompare != 0) {
          return timeCompare;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
      schedule.add(DaySchedule(weekday: weekday, items: items));
    }

    return schedule;
  }

  Future<List<DaySchedule>> _buildScheduleFromBgmListApi({
    bool forceRefresh = false,
  }) async {
    await _ensureBgmListScheduleCandidatesLoaded(forceRefresh: forceRefresh);
    if (_bgmScheduleCandidates.isEmpty) {
      return <DaySchedule>[];
    }

    final List<BgmListScheduleCandidate> currentSeason =
        await _resolveCurrentSeasonCandidates(_bgmScheduleCandidates);
    _appendDebugLog('日历: BGMLIST 当期条目 ${currentSeason.length} 条');
    return _buildScheduleFromCandidates(currentSeason);
  }

  Future<void> _refreshCalendarSchedule({
    bool initial = false,
    bool forceNetwork = false,
  }) async {
    setState(() {
      _isLoadingSchedule = true;
      _scheduleError = '';
    });
    _showStatus(forceNetwork ? '正在抓取每日放送...' : '正在加载日历...', autoHide: false);

    try {
      final bool needAutoNetwork = !forceNetwork && initial
          ? await _shouldAutoRefreshOnMonthFirst()
          : false;
        final bool cacheTimezoneMatched = await _isCalendarCacheTimezoneMatched();

        if (!forceNetwork && !needAutoNetwork && cacheTimezoneMatched) {
        final List<DaySchedule> cachedSchedule = await _calendarCacheManager
            .load();
        if (cachedSchedule.isNotEmpty) {
          if (!mounted) {
            return;
          }
          _applyScheduleData(
            cachedSchedule,
            doneStatusText: initial ? '已从本地缓存加载日历' : '日历已从本地缓存刷新',
          );
          await _archiveMissingWatchlistItemsAfterCalendar(cachedSchedule);
          unawaited(_hydrateCachedCoversForTodayItems());
          unawaited(_hydrateCachedCoversForWatchlistItems());
          return;
        }
      }

      if (!cacheTimezoneMatched) {
        _appendDebugLog('日历缓存时区不匹配，跳过缓存并重新抓取');
      }

      final bool shouldRefetchBgmSource = forceNetwork || needAutoNetwork;
      final List<DaySchedule> mergedScheduleJst =
          await _buildScheduleFromBgmListApi(
        forceRefresh: shouldRefetchBgmSource,
      );
      final List<DaySchedule> mergedSchedule = _convertScheduleFromJstForDisplay(
        mergedScheduleJst,
      );
      await _calendarCacheManager.save(mergedSchedule);
      await _saveCalendarCacheTimezoneToken();

      if (needAutoNetwork) {
        await _markAutoRefreshDoneForCurrentMonth();
      }

      if (!mounted) {
        return;
      }

      _applyScheduleData(
        mergedSchedule,
        doneStatusText: forceNetwork || needAutoNetwork
            ? (initial ? '初始化完成' : '日历已刷新')
            : (initial ? '初始化完成（网络）' : '日历已刷新（网络）'),
      );
      await _archiveMissingWatchlistItemsAfterCalendar(mergedSchedule);

      if (forceNetwork || needAutoNetwork) {
        unawaited(_cacheAllCalendarCovers(mergedSchedule));
      } else {
        unawaited(_hydrateCachedCoversForTodayItems());
        unawaited(_hydrateCachedCoversForWatchlistItems());
      }
    } catch (e) {
      _appendDebugLog('刷新日历失败: $e');

      try {
        final List<DaySchedule> cachedSchedule = await _calendarCacheManager
            .load();
        if (cachedSchedule.isNotEmpty) {
          if (!mounted) {
            return;
          }
          _applyScheduleData(
            cachedSchedule,
            doneStatusText: '网络失败，已回退本地缓存日历',
          );
          await _archiveMissingWatchlistItemsAfterCalendar(cachedSchedule);
          unawaited(_hydrateCachedCoversForTodayItems());
          unawaited(_hydrateCachedCoversForWatchlistItems());
          return;
        }
      } catch (_) {
        // Ignore cache fallback failures and report original error below.
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingSchedule = false;
        _scheduleError = e.toString();
      });
      _showStatus('获取每日放送失败');
    }
  }

  
  List<SubjectItem> _resolveTodayItemsFromSchedule(List<DaySchedule> schedule) {
    return schedule
        .where((DaySchedule day) => day.weekday == _effectiveTodayWeekday)
        .expand((DaySchedule day) => day.items)
        .toList();
  }

  
  String _normalizeTitleStrict(String raw) {
    String value = raw.toLowerCase();
    value = value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\u4e00-\u9fffA-Za-z0-9]'), '');
    return value;
  }

  
  String _normalizeTitleLoose(String raw) {
    String value = raw.toLowerCase();
    value = value.replaceAll(RegExp(r'第\s*\d+\s*[期季]'), '');
    value = value.replaceAll(
      RegExp(r'part\.?\s*\d+', caseSensitive: false),
      '',
    );
    value = value.replaceAll(RegExp(r'season\s*\d+', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\([^)]*\)'), '');
    value = value.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    value = value.replaceAll(RegExp(r'（[^）]*）'), '');
    value = value.replaceAll(RegExp(r'【[^】]*】'), '');
    value = value.replaceAll(RegExp(r'\s+'), '');
    value = value.replaceAll(RegExp(r'[^\u4e00-\u9fffA-Za-z0-9]'), '');
    return value;
  }

  
  List<String> _buildLooseNameCandidates(String raw) {
    final Set<String> candidates = <String>{};

    
    void push(String s) {
      final String value = _normalizeTitleLoose(s);
      if (value.length >= 2) {
        candidates.add(value);
      }
    }

    push(raw);

    String stripped = raw;
    stripped = stripped.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    stripped = stripped.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    stripped = stripped.replaceAll(RegExp(r'（[^）]*）'), ' ');
    stripped = stripped.replaceAll(RegExp(r'【[^】]*】'), ' ');
    push(stripped);

    for (final String sep in <String>[
      '/',
      '／',
      '|',
      '｜',
      ':',
      '：',
      '-',
      '–',
      '—',
      '・',
    ]) {
      if (stripped.contains(sep)) {
        final List<String> parts = stripped
            .split(sep)
            .map((String e) => e.trim())
            .where((String e) => e.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          push(parts.first);
        }
      }
    }

    return candidates.toList();
  }

  
  int _containmentScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    if (a == b) {
      return 10000 + a.length;
    }

    final bool contains = a.contains(b) || b.contains(a);
    if (!contains) {
      return 0;
    }

    final int shorter = a.length < b.length ? a.length : b.length;
    final int longer = a.length > b.length ? a.length : b.length;
    if (shorter < 3) {
      return 0;
    }
    return shorter * 100 - (longer - shorter);
  }

  
  int _bigramSimilarityScore(String a, String b) {
    if (a.length < 4 || b.length < 4) {
      return 0;
    }

    
    Set<String> toBigrams(String value) {
      final Set<String> grams = <String>{};
      for (int i = 0; i < value.length - 1; i++) {
        grams.add(value.substring(i, i + 2));
      }
      return grams;
    }

    final Set<String> ga = toBigrams(a);
    final Set<String> gb = toBigrams(b);
    if (ga.isEmpty || gb.isEmpty) {
      return 0;
    }

    int intersection = 0;
    for (final String g in ga) {
      if (gb.contains(g)) {
        intersection++;
      }
    }

    if (intersection == 0) {
      return 0;
    }

    final int unionCount = ga.length + gb.length - intersection;
    if (unionCount <= 0) {
      return 0;
    }

    final double jaccard = intersection / unionCount;
    if (jaccard < 0.62) {
      return 0;
    }

    return (jaccard * 1000).round();
  }

  
  int _editSimilarityScore(String a, String b) {
    if (a.length < 4 || b.length < 4) {
      return 0;
    }

    
    int levenshtein(String s, String t) {
      final int n = s.length;
      final int m = t.length;
      if (n == 0) {
        return m;
      }
      if (m == 0) {
        return n;
      }

      List<int> prev = List<int>.generate(m + 1, (int i) => i);
      List<int> curr = List<int>.filled(m + 1, 0);

      for (int i = 1; i <= n; i++) {
        curr[0] = i;
        for (int j = 1; j <= m; j++) {
          final int cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
          final int deletion = prev[j] + 1;
          final int insertion = curr[j - 1] + 1;
          final int substitution = prev[j - 1] + cost;
          int best = deletion < insertion ? deletion : insertion;
          if (substitution < best) {
            best = substitution;
          }
          curr[j] = best;
        }
        final List<int> temp = prev;
        prev = curr;
        curr = temp;
      }

      return prev[m];
    }

    final int distance = levenshtein(a, b);
    final int maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) {
      return 0;
    }

    final double similarity = 1 - distance / maxLen;
    if (similarity < 0.70) {
      return 0;
    }

    return (similarity * 900).round();
  }

  
  String _matchBgmListTimeForItem(SubjectItem item) {
    if (_bgmOnAirEntries.isEmpty) {
      return '';
    }

    final String jpName = item.nameOrigin.trim();
    final String fallbackName = item.displayName.trim();
    final List<String> names = <String>[
      if (jpName.isNotEmpty) jpName,
      if (jpName.isEmpty && fallbackName.isNotEmpty) fallbackName,
    ];
    if (names.isEmpty) {
      return '';
    }

    final Set<String> strictCandidates = <String>{};
    final Set<String> looseCandidates = <String>{};
    for (final String name in names) {
      final String strict = _normalizeTitleStrict(name);
      if (strict.isNotEmpty) {
        strictCandidates.add(strict);
      }
      looseCandidates.addAll(_buildLooseNameCandidates(name));
    }

    int bestScore = 0;
    String bestTime = '';

    for (final BgmListOnAirEntry entry in _bgmOnAirEntries) {
      if (entry.timeJst.isEmpty) {
        continue;
      }
      for (final String jpTitle in entry.jpTitles) {
        final String strictKey = _normalizeTitleStrict(jpTitle);
        if (strictKey.isNotEmpty && strictCandidates.contains(strictKey)) {
          return entry.timeJst;
        }

        final String looseKey = _normalizeTitleLoose(jpTitle);
        if (looseKey.isEmpty) {
          continue;
        }
        if (looseCandidates.contains(looseKey)) {
          return entry.timeJst;
        }

        for (final String candidate in looseCandidates) {
          final int containment = _containmentScore(candidate, looseKey);
          if (containment > bestScore) {
            bestScore = containment;
            bestTime = entry.timeJst;
          }

          final int bigram = _bigramSimilarityScore(candidate, looseKey);
          if (bigram > bestScore) {
            bestScore = bigram;
            bestTime = entry.timeJst;
          }

          final int edit = _editSimilarityScore(candidate, looseKey);
          if (edit > bestScore) {
            bestScore = edit;
            bestTime = entry.timeJst;
          }
        }
      }
    }

    if (bestScore >= 420) {
      return bestTime;
    }

    return '';
  }

  Future<void> _ensureBgmListEntriesLoaded({bool forceRefresh = false}) async {
    if (!forceRefresh && _bgmOnAirEntries.isNotEmpty) {
      return;
    }
    if (forceRefresh) {
      _appendDebugLog('更新时间: 强制重新抓取 BGMLIST OnAir JSON');
    }

    final String onAirJson = await _service.fetchBgmListOnAirJson();
    if (onAirJson.trim().isEmpty) {
      return;
    }

    final List<BgmListOnAirEntry> parsed = _service.parseBgmListOnAirEntries(
      onAirJson,
    );
    if (parsed.isNotEmpty) {
      _bgmOnAirEntries = parsed;
    }
  }

  // ignore: unused_element
  Future<List<DaySchedule>> _attachBgmListTimesToSchedule(
    List<DaySchedule> schedule,
    {bool forceRefreshBgmTimes = false}
  ) async {
    try {
      await _ensureBgmListEntriesLoaded(forceRefresh: forceRefreshBgmTimes);
      if (_bgmOnAirEntries.isEmpty) {
        return schedule;
      }

      return schedule.map((DaySchedule day) {
        final List<SubjectItem> patchedItems = day.items
            .map(
              (SubjectItem item) =>
                  item.copyWith(updateTime: _matchBgmListTimeForItem(item)),
            )
            .toList();
        return DaySchedule(weekday: day.weekday, items: patchedItems);
      }).toList();
    } catch (_) {
      // Ignore BGMLIST failures and keep main calendar flow available.
      return schedule;
    }
  }

  
  void _applyDebugWeekdayOverride(int? weekday) {
    setState(() {
      _debugWeekdayOverride = weekday;
      _todayItems = _resolveTodayItemsFromSchedule(_scheduleData);
    });
    _showStatus(
      weekday == null ? '已切换为系统时间' : '已调试指定今日为 ${weekdayMap[weekday]}',
    );
    unawaited(_hydrateCachedCoversForTodayItems());
  }

  Future<void> _openWeekdayDebugDialog() async {
    final int? selected = await showDialog<int?>(
      context: context,
      builder: (BuildContext context) {
        int? tempValue = _debugWeekdayOverride;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            final List<DropdownMenuItem<int?>> options =
                <DropdownMenuItem<int?>>[
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text('系统时间（当前：$_systemWeekday）'),
                  ),
                  for (int i = 1; i <= 7; i++)
                    DropdownMenuItem<int?>(
                      value: i,
                      child: Text(weekdayMap[i] ?? '星期$i'),
                    ),
                ];

            return AlertDialog(
              title: const Text('调试：指定今日星期'),
              content: SizedBox(
                width: 320,
                child: DropdownButtonFormField<int?>(
                  initialValue: tempValue,
                  decoration: const InputDecoration(
                    labelText: '程序中“今日”对应星期',
                    border: OutlineInputBorder(),
                  ),
                  items: options,
                  onChanged: (int? value) {
                    setLocalState(() {
                      tempValue = value;
                    });
                  },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(tempValue),
                  child: const Text('应用'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || selected == _debugWeekdayOverride) {
      return;
    }
    _applyDebugWeekdayOverride(selected);
  }

  Future<void> _openDebugLogDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final String logText = _debugLogs.isEmpty
            ? '暂无日志输出。'
            : _debugLogs.join('\n');

        return AlertDialog(
          title: const Text('调试日志窗口'),
          content: SizedBox(
            width: 760,
            height: 460,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  logText,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                setState(() {
                  _debugLogs.clear();
                  _appendDebugLog('日志已手动清空');
                });
                Navigator.of(context).pop();
              },
              child: const Text('清空并关闭'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _archiveCurrentWatchlistForDebug() async {
    final List<SubjectItem> targets = _watchlist
        .where((SubjectItem item) => item.subjectId.isNotEmpty)
        .toList();
    if (targets.isEmpty) {
      _showStatus('调试归档：当前没有可归档的关注番剧');
      return;
    }

    final String quarter = _currentQuarterLabel();
    final List<WatchArchiveEntry> entries = targets
        .map(
          (SubjectItem item) =>
              WatchArchiveEntry.fromSubject(item, quarter: quarter),
        )
        .toList();
    await _watchArchiveStore.appendEntries(entries);
    _appendDebugLog('调试归档：已写入 ${entries.length} 条关注归档记录');
    _showStatus('调试归档完成：已加入 ${entries.length} 部番剧');
  }

  Future<void> _openDebugToolsDialog() async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.terminal_outlined),
                title: const Text('打开日志窗口'),
                subtitle: const Text('查看状态、网络与错误输出'),
                onTap: () => Navigator.of(context).pop('logs'),
              ),
              ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('调试今日星期'),
                subtitle: const Text('指定程序中的“今日”星期值'),
                onTap: () => Navigator.of(context).pop('weekday'),
              ),
              ListTile(
                leading: Icon(
                  _debugShowChartHoverHitArea
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                title: const Text('悬停判定区域可视化'),
                subtitle: Text(
                  _debugShowChartHoverHitArea ? '当前: 已开启' : '当前: 已关闭',
                ),
                onTap: () => Navigator.of(context).pop('hover-hit-area'),
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('调试：归档当前关注'),
                subtitle: const Text('立即将当前关注番剧写入关注归档'),
                onTap: () => Navigator.of(context).pop('archive-current-watch'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'logs') {
      _appendDebugLog('已打开日志窗口');
      await _openDebugLogDialog();
      return;
    }

    if (action == 'weekday') {
      await _openWeekdayDebugDialog();
      return;
    }

    if (action == 'archive-current-watch') {
      await _archiveCurrentWatchlistForDebug();
      return;
    }

    if (action == 'hover-hit-area') {
      setState(() {
        _debugShowChartHoverHitArea = !_debugShowChartHoverHitArea;
      });
      _showStatus(
        _debugShowChartHoverHitArea ? '已开启悬停判定区域可视化' : '已关闭悬停判定区域可视化',
      );
    }
  }

  Future<void> _hydrateCachedCoversForTodayItems({
    bool fetchMissingFromNetwork = false,
  }) async {
    if (_todayItems.isEmpty) {
      return;
    }

    final List<SubjectItem> source = List<SubjectItem>.from(_todayItems);
    bool changed = false;

    for (int i = 0; i < source.length; i++) {
      final SubjectItem item = source[i];

      if (item.subjectId.isEmpty) {
        continue;
      }

      if (item.localCoverPath.isNotEmpty) {
        final bool exists = await File(item.localCoverPath).exists();
        if (exists) {
          continue;
        }
      }

      final String? localPath = await _coverCacheManager.getCachedPath(
        item.subjectId,
      );

      String? resolvedLocalPath = localPath;
      if (resolvedLocalPath == null &&
          fetchMissingFromNetwork &&
          item.coverUrl.isNotEmpty) {
        try {
          resolvedLocalPath = await _coverCacheManager.ensureCached(
            subjectId: item.subjectId,
            imageUrl: item.coverUrl,
            fetch: _service.fetchImageWithRetry,
          );
        } catch (_) {
          resolvedLocalPath = null;
        }
      }

      if (resolvedLocalPath != null && resolvedLocalPath.isNotEmpty) {
        source[i] = item.copyWith(localCoverPath: resolvedLocalPath);
        changed = true;
      }
    }

    if (!mounted || !changed) {
      return;
    }

    setState(() {
      _todayItems = source;
    });
  }

  Future<void> _hydrateCachedCoversForWatchlistItems() async {
    if (_watchlist.isEmpty) {
      return;
    }

    final List<SubjectItem> source = List<SubjectItem>.from(_watchlist);
    bool changed = false;

    for (int i = 0; i < source.length; i++) {
      final SubjectItem item = source[i];
      if (item.subjectId.isEmpty) {
        continue;
      }

      if (item.localCoverPath.isNotEmpty) {
        final bool exists = await File(item.localCoverPath).exists();
        if (exists) {
          continue;
        }
      }

      final String? localPath = await _coverCacheManager.getCachedPath(
        item.subjectId,
      );
      if (localPath != null && localPath.isNotEmpty) {
        source[i] = item.copyWith(localCoverPath: localPath);
        changed = true;
      }
    }

    if (!mounted || !changed) {
      return;
    }

    setState(() {
      _watchlist = source;
    });
  }

  Future<void> _hydrateCachedCoversForScheduleItems() async {
    if (_scheduleData.isEmpty) {
      return;
    }

    final List<DaySchedule> patched = <DaySchedule>[];
    bool changed = false;

    for (final DaySchedule day in _scheduleData) {
      final List<SubjectItem> items = <SubjectItem>[];
      for (final SubjectItem item in day.items) {
        if (item.subjectId.isEmpty) {
          items.add(item);
          continue;
        }

        if (item.localCoverPath.isNotEmpty) {
          final bool exists = await File(item.localCoverPath).exists();
          if (exists) {
            items.add(item);
            continue;
          }
        }

        final String? localPath = await _coverCacheManager.getCachedPath(
          item.subjectId,
        );
        if (localPath != null && localPath.isNotEmpty) {
          items.add(item.copyWith(localCoverPath: localPath));
          changed = true;
        } else {
          items.add(item);
        }
      }
      patched.add(DaySchedule(weekday: day.weekday, items: items));
    }

    if (!mounted || !changed) {
      return;
    }

    final Map<String, String> localPathBySubjectId = <String, String>{};
    for (final DaySchedule day in patched) {
      for (final SubjectItem item in day.items) {
        if (item.subjectId.isNotEmpty && item.localCoverPath.isNotEmpty) {
          localPathBySubjectId[item.subjectId] = item.localCoverPath;
        }
      }
    }

    setState(() {
      _scheduleData = patched;
      _allItems = _allItems.map((SubjectItem item) {
        final String? localPath = localPathBySubjectId[item.subjectId];
        if (localPath == null || localPath.isEmpty) {
          return item;
        }
        return item.copyWith(localCoverPath: localPath);
      }).toList();
      _todayItems = _todayItems.map((SubjectItem item) {
        final String? localPath = localPathBySubjectId[item.subjectId];
        if (localPath == null || localPath.isEmpty) {
          return item;
        }
        return item.copyWith(localCoverPath: localPath);
      }).toList();
    });
  }

  Future<void> _cacheAllCalendarCovers(List<DaySchedule> schedule) async {
    if (_isCachingCalendarCovers) {
      return;
    }

    final Map<String, SubjectItem> merged = <String, SubjectItem>{};
    for (final DaySchedule day in schedule) {
      for (final SubjectItem item in day.items) {
        if (item.subjectId.isEmpty || merged.containsKey(item.subjectId)) {
          continue;
        }
        merged[item.subjectId] = item;
      }
    }

    if (merged.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _isCachingCalendarCovers = true;
        _calendarCoverCacheDone = 0;
        _calendarCoverCacheTotal = merged.length;
      });
    }

    _showStatus('正在缓存日历封面...', autoHide: false);

    final Set<String> todayIds = _resolveTodayItemsFromSchedule(schedule)
        .where((SubjectItem item) => item.subjectId.isNotEmpty)
        .map((SubjectItem item) => item.subjectId)
        .toSet();

    final List<SubjectItem> all = <SubjectItem>[
      ...merged.values.where(
        (SubjectItem item) => todayIds.contains(item.subjectId),
      ),
      ...merged.values.where(
        (SubjectItem item) => !todayIds.contains(item.subjectId),
      ),
    ];
    final List<SubjectItem> updated = List<SubjectItem>.from(all);
    int cachedCount = 0;
    int skippedNoCoverUrl = 0;
    int fetchedFromSubjectPage = 0;
    int processedCount = 0;

    final int maxParallelWorkers = _settingCoverCacheConcurrency;
    int nextIndex = 0;

    
    int? takeNextIndex() {
      if (nextIndex >= updated.length) {
        return null;
      }
      final int current = nextIndex;
      nextIndex += 1;
      return current;
    }

    
    void applyRealtimeUpdate(SubjectItem fresh) {
      if (!mounted || fresh.subjectId.isEmpty) {
        return;
      }

      setState(() {
        final int allIndex = _allItems.indexWhere(
          (SubjectItem x) => x.subjectId == fresh.subjectId,
        );
        if (allIndex >= 0) {
          final SubjectItem prev = _allItems[allIndex];
          _allItems[allIndex] = prev.copyWith(
            coverUrl: fresh.coverUrl.isNotEmpty
                ? fresh.coverUrl
                : prev.coverUrl,
            localCoverPath: fresh.localCoverPath.isNotEmpty
                ? fresh.localCoverPath
                : prev.localCoverPath,
          );
        }

        final int todayIndex = _todayItems.indexWhere(
          (SubjectItem x) => x.subjectId == fresh.subjectId,
        );
        if (todayIndex >= 0) {
          final SubjectItem prev = _todayItems[todayIndex];
          _todayItems[todayIndex] = prev.copyWith(
            coverUrl: fresh.coverUrl.isNotEmpty
                ? fresh.coverUrl
                : prev.coverUrl,
            localCoverPath: fresh.localCoverPath.isNotEmpty
                ? fresh.localCoverPath
                : prev.localCoverPath,
          );
        }

        final int watchIndex = _watchlist.indexWhere(
          (SubjectItem x) => x.subjectId == fresh.subjectId,
        );
        if (watchIndex >= 0) {
          final SubjectItem prev = _watchlist[watchIndex];
          _watchlist[watchIndex] = prev.copyWith(
            coverUrl: fresh.coverUrl.isNotEmpty
                ? fresh.coverUrl
                : prev.coverUrl,
            localCoverPath: fresh.localCoverPath.isNotEmpty
                ? fresh.localCoverPath
                : prev.localCoverPath,
            updateTime: fresh.updateTime.isNotEmpty
                ? fresh.updateTime
                : prev.updateTime,
          );
        }

        _scheduleData = _scheduleData.map((DaySchedule day) {
          final List<SubjectItem> nextItems = day.items.map((SubjectItem item) {
            if (item.subjectId != fresh.subjectId) {
              return item;
            }
            return item.copyWith(
              coverUrl: fresh.coverUrl.isNotEmpty
                  ? fresh.coverUrl
                  : item.coverUrl,
              localCoverPath: fresh.localCoverPath.isNotEmpty
                  ? fresh.localCoverPath
                  : item.localCoverPath,
              updateTime: fresh.updateTime.isNotEmpty
                  ? fresh.updateTime
                  : item.updateTime,
            );
          }).toList();
          return DaySchedule(weekday: day.weekday, items: nextItems);
        }).toList();
      });
    }

    Future<void> processOne(int i) async {
      SubjectItem item = updated[i];

      String? localPath = await _coverCacheManager.getCachedPath(
        item.subjectId,
      );
      if (localPath != null && localPath.isNotEmpty) {
        cachedCount += 1;
        if (item.localCoverPath != localPath) {
          item = item.copyWith(localCoverPath: localPath);
          updated[i] = item;
          applyRealtimeUpdate(item);
        }
        processedCount += 1;
        if (mounted) {
          setState(() {
            _calendarCoverCacheDone = processedCount;
          });
        }
        return;
      }

      String coverUrl = item.coverUrl;
      if (coverUrl.isEmpty && item.subjectUrl.isNotEmpty) {
        try {
          coverUrl = await _service.fetchSubjectCoverUrl(item.subjectUrl);
        } catch (_) {
          coverUrl = '';
        }

        if (coverUrl.isNotEmpty) {
          fetchedFromSubjectPage += 1;
          item = item.copyWith(coverUrl: coverUrl);
          updated[i] = item;
          applyRealtimeUpdate(item);
        }
      }

      if (coverUrl.isEmpty) {
        skippedNoCoverUrl += 1;
        processedCount += 1;
        if (mounted) {
          setState(() {
            _calendarCoverCacheDone = processedCount;
          });
        }
        return;
      }

      if (localPath == null) {
        try {
          _appendDebugLog(
            '网络: 开始抓取[缓存封面文件] $coverUrl (subjectId=${item.subjectId})',
          );
          _appendDebugLog(
            '网络: 开始抓取[缓存封面文件] $coverUrl (subjectId=${item.subjectId})',
          );
          localPath = await _coverCacheManager.ensureCached(
            subjectId: item.subjectId,
            imageUrl: coverUrl,
            fetch: (String url) => _service.fetchImageWithRetry(
              url,
              respectRateLimit: false,
              purpose: '抓取封面文件(全量缓存)',
            ),
          );
        } catch (_) {
          localPath = null;
        }
      }

      if (localPath != null && localPath.isNotEmpty) {
        cachedCount += 1;
        if (item.localCoverPath != localPath) {
          item = item.copyWith(localCoverPath: localPath);
          updated[i] = item;
          applyRealtimeUpdate(item);
        }
      }

      processedCount += 1;
      if (mounted) {
        setState(() {
          _calendarCoverCacheDone = processedCount;
        });
      }
    }

    Future<void> worker() async {
      while (true) {
        final int? i = takeNextIndex();
        if (i == null) {
          return;
        }
        await processOne(i);
      }
    }

    final int workerCount = updated.length < maxParallelWorkers
        ? updated.length
        : maxParallelWorkers;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isCachingCalendarCovers = false;
    });
    _showStatus(
      '全量封面缓存完成（已缓存 $cachedCount/${updated.length}，补抓链接 $fetchedFromSubjectPage，缺少链接跳过 $skippedNoCoverUrl）',
    );
  }

  Future<void> _clearCoverCache() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('清除封面缓存'),
          content: const Text('将删除本地缓存文件夹中的封面图片，是否继续？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final int deleted = await _coverCacheManager.clearAll();
    if (!mounted) {
      return;
    }

    setState(() {
      _todayItems = _todayItems
          .map((SubjectItem item) => item.copyWith(localCoverPath: ''))
          .toList();
      _watchlist = _watchlist
          .map((SubjectItem item) => item.copyWith(localCoverPath: ''))
          .toList();
    });
    _showStatus('已清除封面缓存，共删除 $deleted 个文件');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('封面缓存已清除（$deleted 个文件）')));
  }

  Future<void> _refreshProgress({Set<String>? onlySubjectIds}) async {
    if (_isLoadingProgress) {
      return;
    }

    final Set<String>? allowedIds = onlySubjectIds
      ?.where((String id) => id.isNotEmpty)
      .toSet();
    final bool isScopedRefresh = allowedIds != null;

    bool apiAvailable = false;
    if (!isScopedRefresh) {
      apiAvailable = await _service.isApiAvailable();
    }

    final Map<String, SubjectItem> watchTargets = <String, SubjectItem>{};
    for (final SubjectItem item in _watchlist) {
      if (item.subjectId.isEmpty) {
        continue;
      }
      if (allowedIds != null && !allowedIds.contains(item.subjectId)) {
        continue;
      }
      watchTargets[item.subjectId] = item;
    }

    final Map<String, SubjectItem> targets = <String, SubjectItem>{
      ...watchTargets,
    };

    if (apiAvailable && !isScopedRefresh) {
      for (final SubjectItem item in _todayItems) {
        if (item.subjectId.isEmpty || item.subjectUrl.isEmpty) {
          continue;
        }
        if (targets.containsKey(item.subjectId)) {
          continue;
        }
        targets[item.subjectId] = item;
      }
    }

    final Set<String> todayIds = _resolveTodayItemsFromSchedule(_scheduleData)
        .map((SubjectItem item) => item.subjectId)
        .where((String id) => id.isNotEmpty)
        .toSet();

    final Map<String, BroadcastScheduleHint> scheduleHintsBySubjectId =
        <String, BroadcastScheduleHint>{};
    for (final DaySchedule day in _scheduleData) {
      for (final SubjectItem item in day.items) {
        if (item.subjectId.isEmpty) {
          continue;
        }
        if (scheduleHintsBySubjectId.containsKey(item.subjectId)) {
          continue;
        }
        scheduleHintsBySubjectId[item.subjectId] = BroadcastScheduleHint(
          weekday: day.weekday,
          time: item.updateTime,
        );
      }
    }

    final Map<String, int> watchOrderIndex = <String, int>{
      for (int i = 0; i < _watchlist.length; i++) _watchlist[i].subjectId: i,
    };

    final Map<String, int> todayOrderIndex = <String, int>{
      for (int i = 0; i < _todayItems.length; i++) _todayItems[i].subjectId: i,
    };

    final List<MapEntry<String, SubjectItem>> orderedTargets =
        targets.entries.toList()..sort((
          MapEntry<String, SubjectItem> a,
          MapEntry<String, SubjectItem> b,
        ) {
          
          int rankFor(String id) {
            final bool isFollowed = watchTargets.containsKey(id);
            final bool isToday = todayIds.contains(id);
            if (apiAvailable && !isScopedRefresh) {
              if (isFollowed && isToday) {
                return 0;
              }
              if (isFollowed) {
                return 1;
              }
              if (isToday) {
                return 2;
              }
              return 3;
            }

            if (isToday) {
              return 0;
            }
            if (isFollowed) {
              return 1;
            }
            return 2;
          }

          final int ar = rankFor(a.key);
          final int br = rankFor(b.key);
          if (ar != br) {
            return ar.compareTo(br);
          }

          final int aw = watchOrderIndex[a.key] ?? (1 << 20);
          final int bw = watchOrderIndex[b.key] ?? (1 << 20);
          if (aw != bw) {
            return aw.compareTo(bw);
          }

          final int at = todayOrderIndex[a.key] ?? (1 << 20);
          final int bt = todayOrderIndex[b.key] ?? (1 << 20);
          return at.compareTo(bt);
        });

    if (targets.isEmpty) {
      if (allowedIds != null) {
        _showStatus('关注列表无新增，跳过进度抓取');
      } else {
        _showStatus('没有可更新进度的关注番剧');
      }
      return;
    }

    setState(() {
      _isLoadingProgress = true;
      _progressRefreshDone = 0;
      _progressRefreshTotal = orderedTargets.length;
    });
    _showStatus('正在抓取进度...', autoHide: false);

    int processed = 0;
    int nextIndex = 0;

    
    int? takeNextIndex() {
      if (nextIndex >= orderedTargets.length) {
        return null;
      }
      final int current = nextIndex;
      nextIndex += 1;
      return current;
    }

    Future<void> processOne(MapEntry<String, SubjectItem> entry) async {
      final String sid = entry.key;
      final SubjectItem item = entry.value;
      SubjectProgress rawProgress;

      if (item.subjectUrl.isEmpty) {
        rawProgress = const SubjectProgress(error: '缺少 subject_url');
      } else {
        try {
          _appendDebugLog('网络: 开始抓取[进度] ${item.subjectUrl} (subjectId=$sid)');
          final BroadcastScheduleHint? hint = scheduleHintsBySubjectId[sid];
          rawProgress = await _service.fetchSubjectProgress(
            item.subjectUrl,
            scheduleTime: hint?.time ?? '',
            scheduleWeekday: hint?.weekday ?? '',
            displayTimezoneOffsetMinutes: _effectiveDisplayTimezoneOffsetMinutes,
          );
        } catch (e) {
          _appendDebugLog('网络: 抓取失败[进度] ${item.subjectUrl} ($e)');
          rawProgress = SubjectProgress(error: e.toString());
        }
      }

      final SubjectProgress progress = _applyManualProgressCorrection(
        sid,
        rawProgress,
      );

      processed += 1;
      if (!mounted) {
        return;
      }

      setState(() {
        _rawProgressCache[sid] = rawProgress;
        _progressCache[sid] = progress;
        _progressRefreshDone = processed;
      });
    }

    Future<void> worker() async {
      while (true) {
        if (!mounted) {
          return;
        }
        final int? idx = takeNextIndex();
        if (idx == null) {
          return;
        }
        await processOne(orderedTargets[idx]);
      }
    }

    final int maxParallelWorkers = _settingProgressConcurrency;
    final int workerCount = orderedTargets.length < maxParallelWorkers
        ? orderedTargets.length
        : maxParallelWorkers;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    if (!mounted) {
      return;
    }

    if (_progressCorrectionMigrationDirty) {
      await _saveProgressCorrections();
    }

    setState(() {
      _isLoadingProgress = false;
      _progressRefreshDone = _progressRefreshTotal;
    });
    _showStatus('进度已更新');
  }

  
  Widget _buildTaskProgressOverlay() {
    final bool showStatusText =
        _showStatusText && _statusText.trim().isNotEmpty;
    final bool showCoverProgress =
        _isCachingCalendarCovers && _calendarCoverCacheTotal > 0;
    final bool showRefreshProgress =
        _isLoadingProgress && _progressRefreshTotal > 0;

    if (!showStatusText && !showCoverProgress && !showRefreshProgress) {
      return const SizedBox.shrink();
    }

    double coverValue = 0;
    if (_calendarCoverCacheTotal > 0) {
      coverValue = _calendarCoverCacheDone / _calendarCoverCacheTotal;
    }

    double refreshValue = 0;
    if (_progressRefreshTotal > 0) {
      refreshValue = _progressRefreshDone / _progressRefreshTotal;
    }

    return Align(
      alignment: Alignment.topRight,
      child: IgnorePointer(
        child: Container(
          width: 240,
          margin: const EdgeInsets.only(top: 8, right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.92),
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
                    _statusText,
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
                          value: coverValue.clamp(0, 1),
                          minHeight: 3,
                        ),
                      if (showCoverProgress && showRefreshProgress)
                        const SizedBox(height: 4),
                      if (showRefreshProgress)
                        LinearProgressIndicator(
                          value: refreshValue.clamp(0, 1),
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

  
  String _formatProgress(SubjectProgress? progress) {
    if (progress == null) {
      return '进度: 未获取';
    }
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

  
  String _formatRatingBadge(SubjectProgress? progress) {
    final double? score = progress?.ratingScore;
    if (score == null || score <= 0) {
      return '';
    }
    final String text = score.toStringAsFixed(1);
    return '评分 $text';
  }

  Future<void> _saveSelectedWatchlist() async {
    final Set<String> previousWatchIds = _watchlist
        .map((SubjectItem item) => item.subjectId)
        .where((String id) => id.isNotEmpty)
        .toSet();

    final Map<String, SubjectItem> itemMap = <String, SubjectItem>{
      for (final SubjectItem item in _allItems)
        if (item.subjectId.isNotEmpty) item.subjectId: item,
    };

    final List<SubjectItem> selected = _selectedIds
        .where((String id) => itemMap.containsKey(id))
        .map((String id) => itemMap[id]!)
        .toList();

    final Set<String> selectedIdsNow = selected
        .map((SubjectItem item) => item.subjectId)
        .where((String id) => id.isNotEmpty)
        .toSet();

    final Set<String> newWatchIds = selectedIdsNow.difference(previousWatchIds);
    final Set<String> removedWatchIds = previousWatchIds.difference(
      selectedIdsNow,
    );

    setState(() {
      _watchlist = selected;
      _manualProgressCorrections.removeWhere(
        (String id, int _) => removedWatchIds.contains(id),
      );
      _legacyAbsoluteProgressCorrections.removeWhere(
        (String id, int _) => removedWatchIds.contains(id),
      );
      for (final String removedId in removedWatchIds) {
        _progressCache.remove(removedId);
        _rawProgressCache.remove(removedId);
      }
    });
    _showStatus('已保存 ${_watchlist.length} 部关注番剧');

    await _saveWatchlist();
    if (removedWatchIds.isNotEmpty) {
      await _saveProgressCorrections();
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已保存 ${_watchlist.length} 部关注番剧')));
    await _refreshProgress(onlySubjectIds: newWatchIds);
  }

  
  void _selectAll(bool selected) {
    setState(() {
      if (selected) {
        _selectedIds = _allItems.map((SubjectItem e) => e.subjectId).toSet();
      } else {
        _selectedIds.clear();
      }
    });
  }

  Future<void> _openSubjectInBrowser(SubjectItem item) async {
    final Uri? uri = _resolveSubjectUri(item.subjectUrl);
    if (uri == null) {
      _showStatus('该条目缺少页面链接');
      return;
    }

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        return;
      }
    } catch (_) {}

    final bool fallbackOpened = await _openUrlBySystemCommand(uri);
    if (!fallbackOpened) {
      _showStatus('打开链接失败');
    }
  }

  
  Uri? _resolveSubjectUri(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return null;
    }

    final Uri? parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme && parsed.hasAuthority) {
      return parsed;
    }

    if (value.startsWith('//')) {
      return Uri.tryParse('https:$value');
    }
    if (value.startsWith('/')) {
      return Uri.tryParse('https://bangumi.tv$value');
    }

    return Uri.tryParse('https://bangumi.tv/$value');
  }

  Future<bool> _openUrlBySystemCommand(Uri uri) async {
    final String url = uri.toString();
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', <String>['/c', 'start', '', url]);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', <String>[url]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', <String>[url]);
        return true;
      }
    } catch (_) {
      return false;
    }

    return false;
  }

  Widget _buildSubjectTile({
    required SubjectItem item,
    required int index,
    required bool followed,
    bool showCover = false,
    double coverWidth = 54,
    double coverHeight = 72,
    bool showFollowedBadge = false,
    bool highlightFollowed = false,
    String updateWeekdayText = '',
    String updateTimeText = '',
    bool showRatingBadge = false,
    bool showCommentChart = true,
    bool showCommentTotalBadge = false,
    VoidCallback? onToggleFollow,
    VoidCallback? onAdjustProgress,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final SubjectProgress? progress = _progressCache[item.subjectId];
    final int totalCommentCount = progress == null
        ? 0
        : progress.episodeCommentCounts.fold<int>(
            0,
            (int sum, int value) => sum + value,
          );
    final String ratingText = showRatingBadge
        ? _formatRatingBadge(progress)
        : '';
    final bool isHighRating = (progress?.ratingScore ?? 0) >= 7.5;
    final String title = item.displayName.isNotEmpty
        ? item.displayName
        : item.subjectId;
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
                onTap: () => _openSubjectInBrowser(item),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.localCoverPath.isNotEmpty
                      ? Image.file(
                          File(item.localCoverPath),
                          width: coverWidth,
                          height: coverHeight,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stackTrace) =>
                              _buildCoverPlaceholder(
                                width: coverWidth,
                                height: coverHeight,
                              ),
                        )
                      : item.coverUrl.isNotEmpty
                      ? Image.network(
                          item.coverUrl,
                          width: coverWidth,
                          height: coverHeight,
                          fit: BoxFit.cover,
                          headers: imageRequestHeaders,
                          errorBuilder: (_, error, stackTrace) =>
                              _buildCoverPlaceholder(
                                width: coverWidth,
                                height: coverHeight,
                              ),
                        )
                      : _buildCoverPlaceholder(
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
                        progress.error == null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (BuildContext context, BoxConstraints box) {
                            final EpisodeCommentChartLayout baseLayout =
                                _commentChartLayout;
                            final double chartWidth = baseLayout.width
                                .clamp(1.0, math.max(1.0, box.maxWidth))
                                .toDouble();
                            final double chartHeight = baseLayout.height
                                .clamp(1.0, math.max(1.0, box.maxHeight))
                                .toDouble();

                            final double freeWidth = math.max(
                              0,
                              box.maxWidth - chartWidth,
                            );
                            final double freeHeight = math.max(
                              0,
                              box.maxHeight - chartHeight,
                            );

                            final double anchorLeft =
                                ((baseLayout.alignment.x + 1) / 2) * freeWidth;
                            final double anchorTop =
                                ((baseLayout.alignment.y + 1) / 2) * freeHeight;

                            final double minOffsetX = -anchorLeft;
                            final double maxOffsetX = freeWidth - anchorLeft;
                            final double minOffsetY = -anchorTop;
                            final double maxOffsetY = freeHeight - anchorTop;

                            final double effectiveOffsetX = baseLayout.offsetX
                                .clamp(minOffsetX, maxOffsetX)
                                .toDouble();
                            final double effectiveOffsetY = baseLayout.offsetY
                                .clamp(minOffsetY, maxOffsetY)
                                .toDouble();

                            final double chartLeft = anchorLeft +
                                effectiveOffsetX;
                            final double chartTop = anchorTop +
                                effectiveOffsetY;

                            return Stack(
                              children: <Widget>[
                                Positioned(
                                  left: chartLeft,
                                  top: chartTop,
                                  width: chartWidth,
                                  height: chartHeight,
                                  child: _buildEpisodeCommentBarChart(
                                    progress.episodeCommentCounts,
                                    layout: EpisodeCommentChartLayout(
                                      alignment: baseLayout.alignment,
                                      offsetX: baseLayout.offsetX,
                                      offsetY: baseLayout.offsetY,
                                      width: chartWidth,
                                      height: chartHeight,
                                      headerHeight: baseLayout.headerHeight,
                                      headerBottomGap:
                                          baseLayout.headerBottomGap,
                                      barGap: baseLayout.barGap,
                                      minBarHeight: baseLayout.minBarHeight,
                                      backgroundRadius:
                                          baseLayout.backgroundRadius,
                                      contentPaddingHorizontal:
                                          baseLayout.contentPaddingHorizontal,
                                      contentPaddingVertical:
                                          baseLayout.contentPaddingVertical,
                                        backgroundColor: colors.surface,
                                        backgroundBorderColor:
                                          colors.outlineVariant,
                                    ),
                                    subjectId: item.subjectId,
                                    parentWidth: box.maxWidth,
                                    parentHeight: box.maxHeight,
                                    offsetMinX: minOffsetX,
                                    offsetMaxX: maxOffsetX,
                                    offsetMinY: minOffsetY,
                                    offsetMaxY: maxOffsetY,
                                    effectiveOffsetX: effectiveOffsetX,
                                    effectiveOffsetY: effectiveOffsetY,
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: followedBadgeBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '已关注',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: followedBadgeFg,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            if (updateWeekdayText.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: weekdayBadgeBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  updateWeekdayText,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: weekdayBadgeFg,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                            if (updateTimeText.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: timeBadgeBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  updateTimeText,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: timeBadgeFg,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                            if (ratingText.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isHighRating
                                      ? highRatingBadgeBg
                                      : normalRatingBadgeBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  ratingText,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: isHighRating
                                            ? highRatingBadgeFg
                                            : normalRatingBadgeFg,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                            if (onToggleFollow != null) ...<Widget>[
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
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
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
                          padding: const EdgeInsets.only(top: 8), // 下移
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: onAdjustProgress,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.tune, size: 14),
                                label: const Text('修正更新进度'),
                              ),
                            ),
                        )
                      ],
                    ),
                    if (showCommentTotalBadge)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: commentTotalBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: commentTotalBorder),
                          ),
                          child: Text(
                            '总评 $totalCommentCount',
                            style: Theme.of(context).textTheme.labelSmall
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

  
  Widget _buildCoverPlaceholder({double width = 54, double height = 72}) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_creation_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildEpisodeCommentBarChart(
    List<int> counts, {
    required EpisodeCommentChartLayout layout,
    required String subjectId,
    required double parentWidth,
    required double parentHeight,
    required double offsetMinX,
    required double offsetMaxX,
    required double offsetMinY,
    required double offsetMaxY,
    required double effectiveOffsetX,
    required double effectiveOffsetY,
  }) {
    final List<int> values = counts
        .map((int value) => math.max(0, value))
        .toList(growable: false);
    final int maxCount = values.fold<int>(
      0,
      (int prev, int value) => math.max(prev, value),
    );
    final double barsHeight = math.max(
      0,
      layout.height - layout.headerHeight - layout.headerBottomGap,
    );
    final double barsWidth = math.max(
      0,
      layout.width - layout.contentPaddingHorizontal * 2,
    );
    final int barCount = values.length;

    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color baseColor = colors.primary;

    return MouseRegion(
      opaque: true,
      onExit: (_) {
        if (_hoveredChartSubjectId != subjectId) {
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _hoveredChartSubjectId = null;
          _hoveredChartBarIndex = null;
          _debugHoverLocalX = null;
          _debugHoverLocalY = null;
          _debugHoverBarCount = null;
        });
      },
      onHover: (event) {
        final int localX = event.localPosition.dx.round();
        final int localY = event.localPosition.dy.round();

        int? index;
        if (barCount > 0) {
          final double barTop =
              layout.contentPaddingVertical +
              layout.headerHeight +
              layout.headerBottomGap;
          final double barBottom = barTop + barsHeight;
          final bool insideBarRegion =
              event.localPosition.dy >= barTop &&
              event.localPosition.dy <= barBottom;

          if (insideBarRegion) {
            final double relativeX =
                (event.localPosition.dx - layout.contentPaddingHorizontal)
                    .clamp(0.0, barsWidth)
                    .toDouble();
            final double maxGapByWidth = barCount <= 1
                ? 0
                : barsWidth / (barCount * 2);
            final double effectiveGap = math.min(layout.barGap, maxGapByWidth);
            final double totalGapWidth = effectiveGap * (barCount - 1);
            final double rawBarWidth = (barsWidth - totalGapWidth) / barCount;
            final double barWidth = rawBarWidth.isFinite && rawBarWidth > 0
                ? rawBarWidth
                : 0;
            final double step = barWidth + effectiveGap;

            int computed = step <= 0 ? 0 : (relativeX / step).floor();
            if (computed < 0) {
              computed = 0;
            }
            if (computed >= barCount) {
              computed = barCount - 1;
            }
            index = computed;
          }
        }

        if (_hoveredChartSubjectId == subjectId &&
            _hoveredChartBarIndex == index &&
            _debugHoverLocalX == localX &&
            _debugHoverLocalY == localY &&
            _debugHoverBarCount == barCount) {
          return;
        }

        if (!mounted) {
          return;
        }
        setState(() {
          _hoveredChartSubjectId = subjectId;
          _hoveredChartBarIndex = index;
          _debugHoverLocalX = localX;
          _debugHoverLocalY = localY;
          _debugHoverBarCount = barCount;
        });
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
                  Text('分集评论热度', style: Theme.of(context).textTheme.labelSmall),
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
                  final double chartBarsHeight = math.max(
                    0,
                    constraints.maxHeight,
                  );
                  if (values.isEmpty) {
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: constraints.maxWidth,
                        height: layout.minBarHeight,
                        decoration: BoxDecoration(
                          color: baseColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }

                  final int barCount = values.length;
                  final double maxGapByWidth = barCount <= 1
                      ? 0
                      : constraints.maxWidth / (barCount * 2);
                  final double effectiveGap = math.min(
                    layout.barGap,
                    maxGapByWidth,
                  );
                  final double totalGapWidth = effectiveGap * (barCount - 1);
                  final double rawBarWidth =
                      (constraints.maxWidth - totalGapWidth) / barCount;
                  final double barWidth =
                      rawBarWidth.isFinite && rawBarWidth > 0 ? rawBarWidth : 0;

                  final int? hoveredIndex = _hoveredChartSubjectId == subjectId
                      ? _hoveredChartBarIndex
                      : null;
                  final int? debugLocalX = _hoveredChartSubjectId == subjectId
                      ? _debugHoverLocalX
                      : null;
                  final int? debugLocalY = _hoveredChartSubjectId == subjectId
                      ? _debugHoverLocalY
                      : null;
                  final int? debugBarCount = _hoveredChartSubjectId == subjectId
                      ? _debugHoverBarCount
                      : null;

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
                          final Color color =
                              Color.lerp(
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
                      if (_debugShowChartHoverHitArea)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: List<Widget>.generate(barCount, (
                                int i,
                              ) {
                                final double cellWidth =
                                    barWidth +
                                    (i == barCount - 1 ? 0 : effectiveGap);
                                final bool active = hoveredIndex == i;

                                return SizedBox(
                                  width: cellWidth,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: active
                                          ? colors.primary.withValues(alpha: 0.33)
                                          : colors.secondary.withValues(alpha: 0.14),
                                      border: Border.all(
                                        color: active
                                            ? colors.primary
                                            : colors.secondary.withValues(
                                                alpha: 0.72,
                                              ),
                                        width: active ? 1.2 : 0.8,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      if (hoveredIndex != null &&
                          hoveredIndex >= 0 &&
                          hoveredIndex < barCount)
                        Positioned(
                          top: -24,
                          left: (() {
                            final double step = barWidth + effectiveGap;
                            final double center =
                                hoveredIndex * step + barWidth / 2;
                            const double labelWidth = 76;
                            final double maxLeft = math
                                .max(0.0, constraints.maxWidth - labelWidth)
                                .toDouble();
                            return (center - labelWidth / 2)
                                .clamp(0.0, maxLeft)
                                .toDouble();
                          })(),
                          child: IgnorePointer(
                            child: Container(
                              width: 76,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.inverseSurface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '评论 ${values[hoveredIndex]}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: colors.onInverseSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      if (_debugShowChartHoverHitArea)
                        Positioned(
                          left: 2,
                          bottom: 2,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colors.inverseSurface.withValues(
                                  alpha: 0.86,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'x:${debugLocalX ?? '-'} y:${debugLocalY ?? '-'} '
                                'idx:${hoveredIndex ?? '-'} n:${debugBarCount ?? barCount}\n'
                                'Pw:${parentWidth.toStringAsFixed(1)} '
                                'Ph:${parentHeight.toStringAsFixed(1)}\n'
                                'W:${layout.width.toStringAsFixed(1)} '
                                'H:${layout.height.toStringAsFixed(1)}\n'
                                'offX[${offsetMinX.toStringAsFixed(1)},${offsetMaxX.toStringAsFixed(1)}] '
                                'cur:${layout.offsetX.toStringAsFixed(1)} '
                                'applied:${effectiveOffsetX.toStringAsFixed(1)}\n'
                                'offY(bottom)[${offsetMinY.toStringAsFixed(1)},${offsetMaxY.toStringAsFixed(1)}] '
                                'cur:${layout.offsetY.toStringAsFixed(1)} '
                                'applied:${effectiveOffsetY.toStringAsFixed(1)}',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: colors.onInverseSurface,
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

  
  Widget _buildNetworkActivityIndicator() {
    if (!_showNetworkIndicator) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: IgnorePointer(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  
  Widget _buildAppBarLogoLayer() {
    final double logoTop =
        -_appBarLogoHeight - _appBarLogoGapAboveTabBar + _appBarLogoOffsetY;
    final double opacity = _appBarLogoOpacity.clamp(0.0, 1.0).toDouble();

    return Positioned(
      left: 0,
      right: 0,
      top: logoTop,
      child: IgnorePointer(
        child: Align(
          alignment: _appBarLogoAlignment,
          child: Padding(
            padding: _appBarLogoPadding,
            child: Transform.translate(
              offset: const Offset(_appBarLogoOffsetX, 0),
              child: Opacity(
                opacity: opacity,
                child: SvgPicture.asset(
                  _appBarLogoAsset,
                  width: _appBarLogoWidth,
                  height: _appBarLogoHeight,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  
  PreferredSizeWidget _buildAppBarBottom() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kTextTabBarHeight),
      child: ClipRect(
        clipper: const _BottomEdgeOnlyClipper(),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            const TabBar(
              tabs: <Widget>[
                Tab(text: '今日更新'),
                Tab(text: '我的关注'),
                Tab(text: '番剧周历'),
                Tab(text: '选择关注'),
              ],
            ),
            _buildAppBarLogoLayer(),
          ],
        ),
      ),
    );
  }

  
  bool _shouldShowAppBarBackgroundImage() {
    if (!_settingAppBarBackgroundImageEnabled) {
      return false;
    }
    return _settingAppBarBackgroundImagePath.trim().isNotEmpty;
  }

  
  String _normalizeBackgroundImageSource(String raw) {
    String value = raw.trim();
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  Widget _buildAppBarBackgroundImage({
    required int? cacheWidth,
  }) {
    final String source = _normalizeBackgroundImageSource(
      _settingAppBarBackgroundImagePath,
    );
    final Color fallbackColor =
        Theme.of(context).appBarTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface;

    
    Widget buildFallback() {
      return ColoredBox(color: fallbackColor);
    }

    if (source.isEmpty) {
      return buildFallback();
    }

    if (source.startsWith('http://') || source.startsWith('https://')) {
      final Uri? uri = Uri.tryParse(source);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        return buildFallback();
      }
      return Image.network(
        source,
        fit: _appBarBackgroundImageFit,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.low,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, Object error, StackTrace? stackTrace) =>
            buildFallback(),
      );
    }

    if (source.startsWith('assets/')) {
      return Image.asset(
        source,
        fit: _appBarBackgroundImageFit,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.low,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, Object error, StackTrace? stackTrace) =>
            buildFallback(),
      );
    }

    // UNC network shares can block on Windows when host is unavailable.
    if (source.startsWith(r'\\')) {
      return buildFallback();
    }

    return Image.file(
      File(source),
      fit: _appBarBackgroundImageFit,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.low,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, Object error, StackTrace? stackTrace) =>
          buildFallback(),
    );
  }

  
  Widget _buildAppBarFlexibleBackground() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double overlayAlpha = isDark ? 0.28 : 0.12;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double dpr = MediaQuery.of(context).devicePixelRatio.clamp(
          1.0,
          3.0,
        );
        final int? cacheWidth = constraints.maxWidth.isFinite
            ? math.max(1, (constraints.maxWidth * dpr).round())
            : null;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _buildAppBarBackgroundImage(
              cacheWidth: cacheWidth,
            ),
            ColoredBox(
              color: Colors.black.withValues(alpha: overlayAlpha),
            ),
          ],
        );
      },
    );
  }

  
  Widget _buildTodayTab() {
    if (_isLoadingSchedule) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_scheduleError.isNotEmpty) {
      return Center(child: Text('获取失败: $_scheduleError'));
    }

    final Set<String> watchIds = _watchlist
        .map((SubjectItem item) => item.subjectId)
        .toSet();
    final List<SubjectItem> followedItems = _todayItems
        .where((SubjectItem item) => watchIds.contains(item.subjectId))
        .toList();
    final List<SubjectItem> unfollowedItems = _todayItems
        .where((SubjectItem item) => !watchIds.contains(item.subjectId))
        .toList();

    
    int compareByUpdateTime(SubjectItem a, SubjectItem b) {
      final int aMinutes = _parseUpdateTimeMinutes(a.updateTime);
      final int bMinutes = _parseUpdateTimeMinutes(b.updateTime);
      final int timeCompare = aMinutes.compareTo(bMinutes);
      if (timeCompare != 0) {
        return timeCompare;
      }

      final String aName = a.displayName.isNotEmpty
          ? a.displayName
          : a.subjectId;
      final String bName = b.displayName.isNotEmpty
          ? b.displayName
          : b.subjectId;
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
              Text('今天是 $_effectiveTodayWeekday，今日更新 ${_todayItems.length} 部。'),
              Text('当前时区: $_currentTimezoneFullLabel'),
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
                    return _buildSubjectTile(
                      item: item,
                      index: index + 1,
                      followed: followed,
                      showCover: true,
                      coverWidth: 72,
                      coverHeight: 96,
                      showFollowedBadge: true,
                      highlightFollowed: true,
                      updateTimeText: item.updateTime,
                      showRatingBadge: true,
                      showCommentChart: false,
                      showCommentTotalBadge: true,
                      onToggleFollow: () => _toggleWatchFromToday(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _toggleWatchFromToday(SubjectItem item) async {
    final bool alreadyFollowed = _watchlist.any(
      (SubjectItem x) => x.subjectId == item.subjectId,
    );

    if (alreadyFollowed) {
      setState(() {
        _watchlist = _watchlist
            .where((SubjectItem x) => x.subjectId != item.subjectId)
            .toList();
        _selectedIds.remove(item.subjectId);
        _manualProgressCorrections.remove(item.subjectId);
        _legacyAbsoluteProgressCorrections.remove(item.subjectId);
        _progressCache.remove(item.subjectId);
        _rawProgressCache.remove(item.subjectId);
      });
      await _saveWatchlist();
      await _saveProgressCorrections();
      _showStatus('已取消关注：${item.displayName}');
      return;
    }

    setState(() {
      _watchlist = <SubjectItem>[..._watchlist, item];
      _selectedIds.add(item.subjectId);
    });
    await _saveWatchlist();
    _showStatus('已关注：${item.displayName}');
    await _refreshProgress(onlySubjectIds: <String>{item.subjectId});
  }

  Future<void> _openProgressAdjustDialog(SubjectItem item) async {
    final String subjectId = item.subjectId;
    final SubjectProgress? current = _progressCache[subjectId];
    final SubjectProgress? rawCurrent = _rawProgressCache[subjectId];
    if (current == null || (current.error ?? '').isNotEmpty) {
      _showStatus('当前无可修正进度，请先刷新');
      return;
    }

    final SubjectProgress baseProgress = rawCurrent ?? current;
    final int totalEps =
        (baseProgress.totalEpsDeclared ?? baseProgress.totalEpsListed ?? 9999)
            .clamp(
          0,
          9999,
        );
    final int theoreticalEp = _resolveTheoreticalAiredEp(baseProgress).clamp(
      0,
      totalEps,
    );
    final int manualDelta = _manualProgressCorrections[subjectId] ??
        ((_legacyAbsoluteProgressCorrections[subjectId] ?? theoreticalEp) -
            theoreticalEp);
    int tempEp = (theoreticalEp + manualDelta).clamp(
      0,
      totalEps,
    );

    
    String signedDeltaText(int value) {
      if (value > 0) {
        return '+$value';
      }
      return '$value';
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('修正更新进度'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.displayName.isNotEmpty
                          ? item.displayName
                          : subjectId,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '理论进度: EP$theoreticalEp，当前偏移: ${signedDeltaText(tempEp - theoreticalEp)}，目标修正: EP$tempEp',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: () {
                            setLocalState(() {
                              tempEp = math.max(0, tempEp - 1);
                            });
                          },
                          child: const Text('回退 -1'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setLocalState(() {
                              tempEp = math.min(totalEps, tempEp + 1);
                            });
                          },
                          child: const Text('前进 +1'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: '$tempEp',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '输入目标显示集数（0~$totalEps）',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (String value) {
                        final int? parsed = int.tryParse(value.trim());
                        if (parsed == null) {
                          return;
                        }
                        setLocalState(() {
                          tempEp = parsed.clamp(0, totalEps);
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('清除修正'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('保存修正'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == null || !mounted) {
      return;
    }

    setState(() {
      if (confirmed) {
        final int delta = tempEp - theoreticalEp;
        if (delta == 0) {
          _manualProgressCorrections.remove(subjectId);
          _legacyAbsoluteProgressCorrections.remove(subjectId);
        } else {
          _manualProgressCorrections[subjectId] = delta;
          _legacyAbsoluteProgressCorrections.remove(subjectId);
        }
      } else {
        _manualProgressCorrections.remove(subjectId);
        _legacyAbsoluteProgressCorrections.remove(subjectId);
      }

      final SubjectProgress? latest = _rawProgressCache[subjectId] ??
          _progressCache[subjectId];
      if (latest != null) {
        _progressCache[subjectId] = _applyManualProgressCorrection(
          subjectId,
          latest,
        );
      }
    });

    await _saveProgressCorrections();
    _showStatus(confirmed ? '已保存进度修正' : '已清除进度修正');
  }

  
  Widget _buildWatchTab() {
    final Map<String, String> weekdayBySubjectId = <String, String>{};
    final Map<String, String> updateTimeBySubjectId = <String, String>{};

    for (final DaySchedule day in _scheduleData) {
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
          child: Text('关注番剧共 ${_watchlist.length} 部（$_currentTimezoneFullLabel）。'),
        ),
        Expanded(
          child: _watchlist.isEmpty
              ? const Center(child: Text('当前没有关注番剧'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: _watchlist.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SubjectItem item = _watchlist[index];
                    final String weekdayText =
                        weekdayBySubjectId[item.subjectId] ?? '';
                    final String timeText =
                        updateTimeBySubjectId[item.subjectId] ??
                        item.updateTime;
                    return _buildSubjectTile(
                      item: item,
                      index: index + 1,
                      followed: true,
                      showCover: true,
                      coverWidth: 72,
                      coverHeight: 96,
                      showFollowedBadge: false,
                      updateWeekdayText: weekdayText,
                      updateTimeText: timeText,
                      showRatingBadge: true,
                      onAdjustProgress: () => _openProgressAdjustDialog(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  
  Widget _buildSelectTab() {
    final String keyword = _searchController.text.trim().toLowerCase();

    final List<SubjectItem> sortedItems = List<SubjectItem>.from(_allItems)
      ..sort((SubjectItem a, SubjectItem b) {
        final String aName = (a.nameCn.isNotEmpty ? a.nameCn : a.nameOrigin)
            .toLowerCase();
        final String bName = (b.nameCn.isNotEmpty ? b.nameCn : b.nameOrigin)
            .toLowerCase();
        return aName.compareTo(bName);
      });

    final List<SubjectItem> filtered = sortedItems.where((SubjectItem item) {
      final String displayName = item.displayName;
      final String searchText =
          '${displayName.toLowerCase()} ${item.nameOrigin.toLowerCase()} ${item.subjectId.toLowerCase()}';
      return keyword.isEmpty || searchText.contains(keyword);
    }).toList();

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: <Widget>[
              FilledButton(
                onPressed: _saveSelectedWatchlist,
                child: const Text('保存关注'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _selectAll(true),
                child: const Text('全选'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _selectAll(false),
                child: const Text('全不选'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: '搜索番剧',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('没有匹配结果'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: filtered.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SubjectItem item = filtered[index];
                    final String line =
                        item.nameOrigin.isNotEmpty &&
                            item.nameOrigin != item.displayName
                        ? '${item.displayName} / ${item.nameOrigin}'
                        : item.displayName;
                    return CheckboxListTile(
                      value: _selectedIds.contains(item.subjectId),
                      title: Text(line.isEmpty ? item.subjectId : line),
                      onChanged: (bool? checked) {
                        setState(() {
                          if (checked ?? false) {
                            _selectedIds.add(item.subjectId);
                          } else {
                            _selectedIds.remove(item.subjectId);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  
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

  Widget _buildWeekCalendarEntry({
    required SubjectItem item,
    required bool followed,
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
            onTap: () => _openSubjectInBrowser(item),
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
                                _buildWeekCalendarPlaceholder(),
                          )
                        : item.coverUrl.isNotEmpty
                        ? Image.network(
                            item.coverUrl,
                            width: 108,
                            height: 146,
                            fit: BoxFit.cover,
                            headers: imageRequestHeaders,
                            errorBuilder: (_, error, stackTrace) =>
                                _buildWeekCalendarPlaceholder(),
                          )
                        : _buildWeekCalendarPlaceholder(),
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
                            style: Theme.of(context).textTheme.labelSmall
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
                            onTap: () => _toggleWatchFromToday(item),
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

  
  Widget _buildWeekCalendarPlaceholder() {
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

  
  Widget _buildWeekCalendarTab() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Set<String> watchIds = _watchlist
        .map((SubjectItem item) => item.subjectId)
        .where((String id) => id.isNotEmpty)
        .toSet();
    final Map<String, SubjectItem> watchById = <String, SubjectItem>{
      for (final SubjectItem item in _watchlist)
        if (item.subjectId.isNotEmpty) item.subjectId: item,
    };

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

    for (final DaySchedule day in _scheduleData) {
      final String weekday = day.weekday;
      if (!grouped.containsKey(weekday)) {
        continue;
      }

      for (final SubjectItem item in day.items) {
        if (!_weekCalendarShowAll && !watchIds.contains(item.subjectId)) {
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
                value: _weekCalendarShowAll,
                onChanged: (bool value) {
                  setState(() {
                    _weekCalendarShowAll = value;
                  });
                },
              ),
              const SizedBox(width: 8),
              Text(
                '${_weekCalendarShowAll ? '全量显示' : '已关注'}（$_currentTimezoneFullLabel）',
              ),
            ],
          ),
        ),
        Expanded(
          child: totalCount == 0
              ? Center(
                  child: Text(
                    _weekCalendarShowAll
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
                                                  item: entry,
                                                  followed: followed,
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

  @override
  /// 构建当前组件的界面结构。
  Widget build(BuildContext context) {
    final bool useCustomAppBarBackground =
      _shouldShowAppBarBackgroundImage();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          clipBehavior: Clip.hardEdge,
          backgroundColor: useCustomAppBarBackground ? Colors.transparent : null,
          surfaceTintColor: useCustomAppBarBackground ? Colors.transparent : null,
          flexibleSpace:
              useCustomAppBarBackground ? _buildAppBarFlexibleBackground() : null,
          title: const SizedBox.shrink(),
          bottom: _buildAppBarBottom(),
          actions: <Widget>[
            _buildNetworkActivityIndicator(),
            IconButton(
              tooltip: '调试工具',
              onPressed: _openDebugToolsDialog,
              icon: const Icon(Icons.bug_report_outlined),
            ),
            IconButton(
              tooltip: '设置',
              onPressed: _openSettingsDialog,
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              tooltip: '刷新日历',
              onPressed: (_isLoadingSchedule || _isLoadingProgress)
                  ? null
                  : _refreshCalendarFromMainAction,
              icon: const Icon(Icons.calendar_month),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  TabBarView(
                    children: <Widget>[
                      _buildTodayTab(),
                      _buildWatchTab(),
                      _buildWeekCalendarTab(),
                      _buildSelectTab(),
                    ],
                  ),
                  _buildTaskProgressOverlay(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isLoadingProgress ? null : _refreshProgressFromMainAction,
          icon: _isLoadingProgress
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: const Text('刷新进度'),
        ),
      ),
    );
  }
}
