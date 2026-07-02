import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'clash_manager.dart';
import 'constants.dart';
import 'models/broadcast_types.dart';
import 'models/subject_item.dart';
import 'models/subject_progress.dart';
import 'models/watch_archive_entry.dart';
import 'services/bangumi_service.dart';
import 'stores/app_state_store.dart';
import 'stores/calendar_cache_manager.dart';
import 'stores/cover_cache_manager.dart';
import 'stores/watch_archive_store.dart';

TextStyle _styleWithWeight(TextStyle? base, FontWeight weight) {
  return (base ?? const TextStyle()).copyWith(
    fontFamilyFallback: sansFallbacks,
    fontWeight: weight,
    height: 1.28,
  );
}

/// _BottomEdgeOnlyClipper
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

/// Terminates the clash process synchronously on window close, without
/// blocking the close path.
class _ClashExitListener with WindowListener {
  @override
  void onWindowClose() {
    ClashManager.instance.kill();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the local clash proxy so Bangumi API requests can go through.
  try {
    await ClashManager.instance.start();
  } catch (e) {
    // Non-fatal: the app can still work if an external proxy is already
    // running on the configured port.
  }

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
    // Kill the clash process immediately (synchronously) when the window
    // closes, without blocking the close path.
    windowManager.addListener(_ClashExitListener());
  }

  runApp(const BangumiApp());
}

/// BangumiApp
class BangumiApp extends StatefulWidget {
  const BangumiApp({super.key});

  @override
  State<BangumiApp> createState() => _BangumiAppState();
}

/// _BangumiAppState
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

/// BangumiHomePage
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

/// _BangumiHomePageState
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
  bool _settingProxyEnabled = defaultSettingProxyEnabled;
  String _settingProxyHost = defaultSettingProxyHost;
  int _settingProxyPort = defaultSettingProxyPort;
  String _settingProxyBypass = defaultSettingProxyBypass;
  String _settingProxySubscriptionUrl = defaultSettingProxySubscriptionUrl;
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
    final Map<String, String> _searchCoverPaths = <String, String>{};
  Map<String, int> _manualProgressCorrections = <String, int>{};
  Set<String> _selectedIds = <String>{};
  List<SearchSubjectResult> _allSearchResults = <SearchSubjectResult>[];
  int _searchTotalResults = 0;
  int _currentSearchPage = 0;
  bool _isSearching = false;
  String _searchError = '';
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
    // Re-apply the saved subscription URL so clash starts with usable nodes.
    if (_settingProxySubscriptionUrl.trim().isNotEmpty &&
        ClashManager.instance.isRunning) {
      try {
        await ClashManager.instance.stop();
        await ClashManager.instance.applySubscription(
          _settingProxySubscriptionUrl.trim(),
        );
        await ClashManager.instance.start(
          savedSubscriptionUrl: _settingProxySubscriptionUrl.trim(),
        );
      } catch (e) {
        _appendDebugLog('代理: 启动时应用订阅失败 ($e)');
      }
    }
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
    _settingProxyEnabled =
        (jsonMap[proxyEnabledSettingKey] as bool?) ?? defaultSettingProxyEnabled;
    _settingProxyHost =
        (jsonMap[proxyHostSettingKey] as String? ?? defaultSettingProxyHost).trim();
    _settingProxyPort =
        (jsonMap[proxyPortSettingKey] as num?)?.toInt() ?? defaultSettingProxyPort;
    _settingProxyBypass =
        (jsonMap[proxyBypassSettingKey] as String? ?? defaultSettingProxyBypass).trim();
    _settingProxySubscriptionUrl =
        (jsonMap[proxySubscriptionUrlSettingKey] as String? ?? defaultSettingProxySubscriptionUrl)
            .trim();

    _service.apiUserAgent = _settingApiUserAgent.isEmpty
      ? appUserAgent
      : _settingApiUserAgent;
    _service.updateProxySettings(
      _settingProxyEnabled,
      _settingProxyHost,
      _settingProxyPort,
      _settingProxyBypass,
    );
    widget.onThemeModeChanged?.call(_settingThemeMode);
    _appendDebugLog('网络: 当前 API UA: ${_service.effectiveApiUserAgent}');
    _appendDebugLog('时区: 当前显示时区 $_currentTimezoneFullLabel');
    if (_settingProxyEnabled) {
      _appendDebugLog('代理: 已启用 $_settingProxyHost:$_settingProxyPort');
    } else {
      _appendDebugLog('代理: 未启用');
    }
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
      proxyEnabledSettingKey: _settingProxyEnabled,
      proxyHostSettingKey: _settingProxyHost,
      proxyPortSettingKey: _settingProxyPort,
      proxyBypassSettingKey: _settingProxyBypass,
      proxySubscriptionUrlSettingKey: _settingProxySubscriptionUrl,
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

  SubjectProgress _applyCorrection(
    SubjectProgress progress,
    int corrected,
  ) {
    final int? totalEps = progress.totalEpsDeclared ?? progress.totalEpsListed;
    final int clamped = _clampCorrectedEp(corrected, totalEps);
    final int? nextEp = totalEps != null && clamped < totalEps
        ? clamped + 1
        : null;
    final int theoretical = _resolveTheoreticalAiredEp(progress);
    final String? correctedEpTitle = clamped <= 0
        ? null
        : (progress.episodeTitleByEp[clamped]?.trim().isNotEmpty ?? false)
        ? progress.episodeTitleByEp[clamped]
        : (theoretical == clamped ? progress.latestAiredCnTitle : null);

    return SubjectProgress(
      totalEpsDeclared: progress.totalEpsDeclared,
      totalEpsListed: progress.totalEpsListed,
      airedEps: clamped,
      latestAiredEp: clamped > 0 ? clamped : null,
      latestAiredCnTitle: correctedEpTitle,
      latestAiredAtLabel: theoretical == clamped
          ? progress.latestAiredAtLabel
          : null,
      nextEp: nextEp,
      ratingScore: progress.ratingScore,
      episodeCommentCounts: progress.episodeCommentCounts,
      episodeTitleByEp: progress.episodeTitleByEp,
      progressText: totalEps == null ? '$clamped/未知' : '$clamped/$totalEps',
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
      final int theoretical = _resolveTheoreticalAiredEp(progress);
      return _applyCorrection(progress, theoretical + manualDelta);
    }

    final int? legacyAbsolute = _legacyAbsoluteProgressCorrections[subjectId];
    if (legacyAbsolute != null) {
      final SubjectProgress corrected = _applyCorrection(
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
    bool tempProxyEnabled = _settingProxyEnabled;
    String tempProxySubscriptionUrl = _settingProxySubscriptionUrl;
    final TextEditingController subscriptionCtrl = TextEditingController(
      text: tempProxySubscriptionUrl,
    );
    final ThemeMode previousThemeMode = _settingThemeMode;
    final bool previousTimezoneConversionEnabled =
        _settingTimezoneConversionEnabled;
    final int previousTimezoneOffsetMinutes = _settingTimezoneOffsetMinutes;
    final bool previousProxyEnabled = _settingProxyEnabled;
    final List<int> commonTimezoneOffsets = <int>[
      for (int hour = -12; hour <= 14; hour++) hour * 60,
    ];

    // Refresh current proxy node info before showing the dialog.
    unawaited(ClashManager.instance.refreshNodeInfo());

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
                      const Divider(height: 24),
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
                      const Divider(height: 24),
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
                      const Divider(height: 24),
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
                      const Divider(height: 24),
                      // ── Clash / Proxy ──
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: ClashManager.instance.isRunning
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              ClashManager.instance.isRunning
                                  ? (ClashManager.instance.currentNode.isNotEmpty
                                      ? '${ClashManager.instance.currentNode}  ${ClashManager.instance.currentLatency}ms'
                                      : 'Clash: 未就绪')
                                  : 'Clash: 未就绪',
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              setLocalState(() {});
                              try {
                                await ClashManager.instance.stop();
                                await ClashManager.instance.start();
                                await ClashManager.instance.refreshNodeInfo();
                                setLocalState(() {});
                              } catch (e) {
                                setLocalState(() {});
                              }
                            },
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('重启', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: subscriptionCtrl,
                        enableInteractiveSelection: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Clash 订阅链接',
                          hintText: 'https://your-subscription-url',
                        ),
                        onChanged: (String value) {
                          setLocalState(() {
                            tempProxySubscriptionUrl = value.trim();
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: tempProxyEnabled,
                        onChanged: (bool value) {
                          setLocalState(() {
                            tempProxyEnabled = value;
                          });
                        },
                        title: const Text('启用代理'),
                        subtitle: const Text('127.0.0.1:7890（内建 Clash）'),
                      ),
                      const Divider(height: 24),
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

    // Save the subscription URL before setState so we can detect changes.
    final String previousSubscriptionUrl = _settingProxySubscriptionUrl;

    if (confirmed != true || !mounted) {
      return;
    }

    final bool themeModeChanged = previousThemeMode != tempThemeMode;
    final bool timezoneChanged =
        previousTimezoneConversionEnabled != tempTimezoneConversionEnabled ||
        previousTimezoneOffsetMinutes != tempTimezoneOffsetMinutes;
    final bool proxyChanged = previousProxyEnabled != tempProxyEnabled;

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
      _settingProxyEnabled = tempProxyEnabled;
      _settingProxyHost = defaultSettingProxyHost;
      _settingProxyPort = defaultSettingProxyPort;
      _settingProxyBypass = defaultSettingProxyBypass;
      _settingProxySubscriptionUrl =
          subscriptionCtrl.text.trim().isNotEmpty
              ? subscriptionCtrl.text.trim()
              : tempProxySubscriptionUrl;
      _service.apiUserAgent = _settingApiUserAgent.isEmpty
          ? appUserAgent
          : _settingApiUserAgent;
    });
    if (themeModeChanged) {
      widget.onThemeModeChanged?.call(_settingThemeMode);
      _appendDebugLog('主题: 当前模式 ${themeModeDisplayText(_settingThemeMode)}');
    }
    if (proxyChanged) {
      _service.updateProxySettings(
        _settingProxyEnabled,
        _settingProxyHost,
        _settingProxyPort,
        _settingProxyBypass,
      );
    }
    // When the subscription URL changes, regenerate the clash config and
    // restart the proxy so new nodes take effect.
    final String effectiveNewUrl = subscriptionCtrl.text.trim().isNotEmpty
        ? subscriptionCtrl.text.trim()
        : tempProxySubscriptionUrl.trim();
    if (effectiveNewUrl.isNotEmpty &&
        effectiveNewUrl != previousSubscriptionUrl) {
      _appendDebugLog('代理: 正在应用订阅链接…');
      try {
        await ClashManager.instance.stop();
        await ClashManager.instance.applySubscription(
          effectiveNewUrl,
        );
        await ClashManager.instance.start();
        _appendDebugLog('代理: 订阅已生效');
      } catch (e) {
        _appendDebugLog('代理: 订阅应用失败 ($e)');
      }
    }
    await _saveSettings();
    _appendDebugLog('网络: 当前 API UA: ${_service.effectiveApiUserAgent}');
    _appendDebugLog('时区: 当前显示时区 $_currentTimezoneFullLabel');
    if (_settingProxyEnabled) {
      _appendDebugLog('代理: 已启用 $_settingProxyHost:$_settingProxyPort');
    }

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

    // Exclude shows whose broadcast start date (from the BGMLIST archive page,
    // JST) is still in the future.  These shows are kept in the weekly
    // calendar but should not appear in the "today" tab.
    final Map<String, DateTime> startDates = _service.subjectStartDates;
    List<SubjectItem> filteredTodayItems;
    if (startDates.isNotEmpty) {
      final DateTime nowJst = DateTime.now().toUtc().add(
        const Duration(hours: 9),
      );
      filteredTodayItems = todayItems.where((SubjectItem item) {
        final DateTime? start = startDates[item.subjectId];
        return start == null || !start.isAfter(nowJst);
      }).toList();
    } else {
      // No start-date info (e.g. loaded from cache) — keep all.
      filteredTodayItems = todayItems;
    }
    final Map<String, SubjectItem> latestById = <String, SubjectItem>{
      for (final SubjectItem item in allItems)
        if (item.subjectId.isNotEmpty) item.subjectId: item,
    };

    setState(() {
      _scheduleData = schedule;
      _allItems = allItems;
      _todayItems = filteredTodayItems;
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

  /// Fetch the BGMLIST onair API and append any shows that began within the
  /// last year and are confirmed to still be airing.  This catches half-year
  /// (cours-spanning) titles that are not part of the current archive page.
  Future<List<DaySchedule>> _enrichWithOnAirShows(
    List<DaySchedule> schedule,
  ) async {
    try {
      // 1. Fetch the onair JSON.
      final String jsonText = await _service.fetchBgmListOnAirJson();
      final dynamic decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return schedule;
      final dynamic itemsRaw = decoded['items'];
      if (itemsRaw is! List) return schedule;
      if (itemsRaw.isEmpty) return schedule;

      // 2. Collect IDs already in the schedule.
      final Set<String> existingIds = <String>{};
      for (final DaySchedule day in schedule) {
        for (final SubjectItem item in day.items) {
          if (item.subjectId.isNotEmpty) existingIds.add(item.subjectId);
        }
      }

      // 3. Build weekday indices.
      final Map<String, List<SubjectItem>> enriched =
          <String, List<SubjectItem>>{
        for (final String wd in <String>[
          '星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六',
        ])
          wd: <SubjectItem>[],
      };
      for (final DaySchedule day in schedule) {
        enriched[day.weekday]!.addAll(day.items);
      }

      // helper: read a string from dynamic, trimming null/empty.
      String rs(dynamic v) {
        if (v == null) return '';
        final String t = v.toString().trim();
        return t == 'null' ? '' : t;
      }

      // helper: parse a date string, or null.
      DateTime? rd(String s) {
        try {
          return DateTime.parse(s.trim());
        } catch (_) {
          return null;
        }
      }

      // helper: parse ISO string and return JST DateTime.
      DateTime? parseJst(String iso) {
        try {
          return DateTime.parse(iso).toUtc().add(const Duration(hours: 9));
        } catch (_) {
          return null;
        }
      }

      // 4. Filter to candidates whose begin date is within the last year,
      //    have a bangumi id, and aren't already in the schedule.
      final DateTime oneYearAgo = DateTime.now().toUtc().add(
        const Duration(hours: 9),
      ).subtract(const Duration(days: 365));
      final List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[];

      for (final dynamic raw in itemsRaw) {
        if (raw is! Map<String, dynamic>) continue;
        final String beginStr = rs(raw['begin']);
        final DateTime? begin = rd(beginStr);
        if (begin == null || begin.isBefore(oneYearAgo)) continue;

        // Extract bangumi id.
        String bgmId = '';
        final dynamic sites = raw['sites'];
        if (sites is List) {
          for (final dynamic site in sites) {
            if (site is Map<String, dynamic> &&
                rs(site['site']).toLowerCase() == 'bangumi') {
              bgmId = rs(site['id']);
              if (RegExp(r'^\d+$').hasMatch(bgmId)) break;
              bgmId = '';
            }
          }
        }
        if (bgmId.isEmpty || existingIds.contains(bgmId)) continue;
        candidates.add(<String, dynamic>{
          'id': bgmId,
          'title': rs(raw['title']),
        });
      }

      if (candidates.isEmpty) return schedule;

      // 5. Check which candidates are still airing (concurrent, limited).
      final Set<String> stillAiring = <String>{};
      const int maxConcurrency = 4;
      int nextIdx = 0;
      final List<Future<void>> workers = <Future<void>>[];
      for (int w = 0; w < maxConcurrency && w < candidates.length; w++) {
        workers.add(Future<void>(() async {
          while (true) {
            final int idx;
            idx = nextIdx;
            nextIdx++;
            if (idx >= candidates.length) return;
            final String id = candidates[idx]['id'] as String;
            try {
              if (await _service.isSubjectStillAiring(id)) {
                stillAiring.add(id);
                _appendDebugLog('日历: OnAir 补充收录 $id (${candidates[idx]['title']})');
              }
            } catch (_) {}
          }
        }));
      }
      await Future.wait(workers);

      // 6. For still-airing candidates, look up their broadcast day/time from
      //    the onair JSON and add them to the schedule.
      for (final dynamic raw in itemsRaw) {
        if (raw is! Map<String, dynamic>) continue;
        String bgmId = '';
        final dynamic sites = raw['sites'];
        if (sites is List) {
          for (final dynamic site in sites) {
            if (site is Map<String, dynamic> &&
                rs(site['site']).toLowerCase() == 'bangumi') {
              bgmId = rs(site['id']);
              if (RegExp(r'^\d+$').hasMatch(bgmId)) break;
              bgmId = '';
            }
          }
        }
        if (!stillAiring.contains(bgmId)) continue;

        // Broadcast time from the onair JSON.
        final String broadcast = rs(raw['broadcast']);
        String weekday = '';
        String updateTime = '';
        if (broadcast.isNotEmpty) {
          final RegExpMatch? m = RegExp(r'^R/([^/]+)/P(\d+)D$').firstMatch(
            broadcast,
          );
          if (m != null) {
            final DateTime? start = parseJst(m.group(1)!);
            if (start != null) {
              final int wd = start.weekday;
              const List<String> wds = <String>[
                '星期一','星期二','星期三','星期四','星期五','星期六','星期日',
              ];
              weekday = wds[(wd + 6) % 7];
              updateTime =
                  '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
            }
          }
        }
        if (weekday.isEmpty) {
          weekday = '星期日'; // fallback
        }

        final String jpName = rs(raw['title']);
        // Extract Chinese name from titleTranslate if available.
        String cnName = '';
        final dynamic tt = raw['titleTranslate'];
        if (tt is Map) {
          for (final String key in <String>['zh-Hans', 'zh-Hant', 'zh']) {
            final dynamic list = tt[key];
            if (list is List && list.isNotEmpty) {
              final String t = rs(list[0]);
              if (t.isNotEmpty) { cnName = t; break; }
            }
          }
        }
        enriched[weekday]!.add(SubjectItem(
          subjectId: bgmId,
          subjectUrl: 'https://bangumi.tv/subject/$bgmId',
          nameCn: cnName,
          nameOrigin: jpName,
          coverUrl: '',
          updateTime: updateTime,
        ));
      }

      // 7. Rebuild schedule in weekday order.
      final List<DaySchedule> result = <DaySchedule>[];
      for (final String w in <String>[
        '星期一','星期二','星期三','星期四','星期五','星期六','星期日',
      ]) {
        final List<SubjectItem> items = enriched[w]!;
        if (items.isEmpty) continue;
        items.sort((SubjectItem a, SubjectItem b) =>
            a.updateTime.compareTo(b.updateTime));
        result.add(DaySchedule(weekday: w, items: items));
      }
      _appendDebugLog('日历: OnAir 补充 ${stillAiring.length} 部半年番');
      return result;
    } catch (e) {
      _appendDebugLog('日历: OnAir 补充失败 ($e)');
      return schedule;
    }
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

      final List<DaySchedule> mergedScheduleJst =
          await _service.fetchCalendarSchedule();
      final List<DaySchedule> enrichedJst =
          await _enrichWithOnAirShows(mergedScheduleJst);
      final int enrichedCount =
          enrichedJst.fold<int>(0, (int sum, DaySchedule day) => sum + day.items.length) -
          mergedScheduleJst.fold<int>(0, (int sum, DaySchedule day) => sum + day.items.length);
      if (enrichedCount > 0) {
        _appendDebugLog('日历: OnAir 补充后共计 $enrichedCount 部');
      }
      final List<DaySchedule> mergedSchedule = _convertScheduleFromJstForDisplay(
        enrichedJst,
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

  Future<void> _showSubjectDetail(SubjectItem item) async {
    if (item.subjectId.isEmpty) {
      _showStatus('条目 ID 为空');
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return _SubjectDetailBody(
          subjectId: item.subjectId,
          item: item,
          service: _service,
          coverCacheManager: _coverCacheManager,
          isFollowed: _watchlist.any((SubjectItem x) => x.subjectId == item.subjectId),
          onOpenInBrowser: () => _openSubjectInBrowser(item),
          onToggleFollow: () => _toggleWatchFromToday(item),
        );
      },
    );
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
                onTap: () => _showSubjectDetail(item),
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
                      ? _buildCoverPlaceholder(
                          width: coverWidth,
                          height: coverHeight,
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
                Tab(text: '番剧搜索'),
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
      const int pageSize = 20;
      final List<SearchSubjectResult> allResults = <SearchSubjectResult>[];
      final Set<String> seenIds = <String>{};

      // Fetch first page (up to 20 results).
      final SearchSubjectsResponse response =
          await _service.searchSubjects(keyword, limit: pageSize, offset: 0);
      int total = response.total;

      for (final SearchSubjectResult r in response.results) {
        if (seenIds.add(r.subject.subjectId)) {
          allResults.add(r);
        }
      }

      // Fetch remaining pages concurrently (up to max 200 results).
      if (total > pageSize) {
        final int maxOffset = math.min(total, 200);
        final List<Future<SearchSubjectsResponse>> pending =
            <Future<SearchSubjectsResponse>>[];
        for (int offset = pageSize; offset < maxOffset; offset += pageSize) {
          pending.add(_service.searchSubjects(
            keyword,
            limit: pageSize,
            offset: offset,
          ));
        }
        final List<SearchSubjectsResponse> rest = await Future.wait(pending);
        for (final SearchSubjectsResponse page in rest) {
          for (final SearchSubjectResult r in page.results) {
            if (seenIds.add(r.subject.subjectId)) {
              allResults.add(r);
            }
          }
        }
      }

      // Sort by popularity desc, then ratingScore desc
      allResults.sort((SearchSubjectResult a, SearchSubjectResult b) {
        final int popCmp = b.popularity.compareTo(a.popularity);
        if (popCmp != 0) return popCmp;
        final double aScore = a.ratingScore ?? 0;
        final double bScore = b.ratingScore ?? 0;
        return bScore.compareTo(aScore);
      });

      if (!mounted) return;
      setState(() {
        _allSearchResults = allResults;
        _searchTotalResults = allResults.length;
        _isSearching = false;
      });

      // Cache covers through BangumiService (uses Clash proxy).
      // Image.network bypasses the proxy, so we download via
      // the service and display from local files.
      _cacheSearchResultCovers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = '搜索失败：$e';
      });
    }
  }

  Future<void> _cacheSearchResultCovers() async {
    for (final SearchSubjectResult r in _allSearchResults) {
      final String id = r.subject.subjectId;
      if (id.isEmpty || r.subject.coverUrl.isEmpty) continue;
      if (_searchCoverPaths.containsKey(id)) continue;
      try {
        final String? path = await _coverCacheManager.ensureCached(
          subjectId: id,
          imageUrl: r.subject.coverUrl,
          fetch: (String url) => _service.fetchImageWithRetry(
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
  }

  Widget _buildSearchResultCover(SubjectItem item) {
    final String? cached = _searchCoverPaths[item.subjectId];
    if (cached != null && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        width: 72,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _buildCoverPlaceholder(width: 72, height: 96),
      );
    }
    // Image.network doesn't go through the Clash proxy, so it can't reach
    // lain.bgm.tv directly. Show placeholder — cache will fill via
    // _cacheSearchResultCovers() and trigger a rebuild.
    return _buildCoverPlaceholder(width: 72, height: 96);
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
    final bool isFollowed = _watchlist
        .any((SubjectItem x) => x.subjectId == item.subjectId);
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
              onTap: () => _showSubjectDetail(item),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.coverUrl.isNotEmpty
                    ? _buildSearchResultCover(item)
                    : _buildCoverPlaceholder(width: 72, height: 96),
              ),
            ),
            const SizedBox(width: 12),
            // Title + badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  GestureDetector(
                    onTap: () => _showSubjectDetail(item),
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
                  onPressed: () => _toggleWatchFromToday(item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectTab() {
    const int pageSize = 10;
    final int totalPages = _allSearchResults.isEmpty
        ? 0
        : (_allSearchResults.length + pageSize - 1) ~/ pageSize;
    final int pageStart = _currentSearchPage * pageSize;
    final int pageEnd = (pageStart + pageSize).clamp(0, _allSearchResults.length);
    final List<SearchSubjectResult> pageItems = pageStart < _allSearchResults.length
        ? _allSearchResults.sublist(pageStart, pageEnd)
        : <SearchSubjectResult>[];

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
                    itemCount: pageItems.length + 1, // +1 for pagination row
                    itemBuilder: (BuildContext context, int index) {
                      if (index < pageItems.length) {
                        return _buildSearchResultTile(pageItems[index]);
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
                                  ? () => setState(() =>
                                        _currentSearchPage--)
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
                              onPressed: _currentSearchPage + 1 < totalPages
                                  ? () => setState(() =>
                                        _currentSearchPage++)
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
            onTap: () => _showSubjectDetail(item),
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
                        ? _buildWeekCalendarPlaceholder()
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

/// 柱状图渲染器 — 用于评分分布等场景。
class _CommentBarPainter extends CustomPainter {
  _CommentBarPainter({
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
      final int value = values[i];
      final double ratio = value <= 0
          ? 0.08
          : value / maxCount;
      final double barHeight = (chartBarsHeight * ratio).clamp(minBarHeight, chartBarsHeight);
      final Color color = Color.lerp(
        baseColor.withValues(alpha: 0.25),
        baseColor,
        ratio.clamp(0.0, 1.0),
      ) ?? baseColor;

      paint.color = color;
      final double x = startX + i * (barWidth + effectiveGap);
      final double y = chartBarsHeight - barHeight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CommentBarPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.maxCount != maxCount ||
        oldDelegate.barWidth != barWidth ||
        oldDelegate.chartBarsHeight != chartBarsHeight ||
        oldDelegate.effectiveGap != effectiveGap ||
        oldDelegate.minBarHeight != minBarHeight ||
        oldDelegate.baseColor != baseColor;
  }

  double get _totalWidth =>
      values.length * barWidth +
      (values.length - 1) * effectiveGap;
}

/// 条目详情底部弹窗内容。
class _SubjectDetailBody extends StatefulWidget {
  const _SubjectDetailBody({
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
  State<_SubjectDetailBody> createState() => _SubjectDetailBodyState();
}

class _SubjectDetailBodyState extends State<_SubjectDetailBody> {
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
      if (mounted) {
        setState(() {
          _data = data;
          _localCoverPath = localPath;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _error = '加载失败: $e';
          _loading = false;
        });
      }
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
    final String nameCn = _readString(data['name_cn']) ?? widget.item.nameCn;
    final String nameOrigin = _readString(data['name']) ?? widget.item.nameOrigin;

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
              // Top row: header (left) + cover + rating (right)
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
                  // Right column: cover + rating below
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
              // Summary
              if (_readString(data['summary']) case final String summary?)
                _buildSummary(colors, summary),
              const SizedBox(height: 20),
              // Action button
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
        // Title
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
    final double score = _readDouble(rating['score']) ?? 0;
    final int total = _readInt(rating['total']) ?? 0;
    final int rank = _readInt(rating['rank']) ?? 0;

    final dynamic rawCount = rating['count'];
    final List<int> values = List<int>.generate(10, (int i) {
      if (rawCount is Map) {
        return _readInt(rawCount['${i + 1}']) ?? 0;
      }
      return 0;
    });
    final int maxCount = values.fold<int>(0, (int a, int b) => a > b ? a : b);

    final EpisodeCommentChartLayout chartLayout = EpisodeCommentChartLayout(
      alignment: Alignment.centerRight,
      offsetX: 0,
      offsetY: 0,
      width: 250,
      height: 65,
      headerHeight: 13,
      headerBottomGap: 2,
      barGap: 2,
      minBarHeight: 2,
      backgroundRadius: 12,
      contentPaddingHorizontal: 8,
      contentPaddingVertical: 5,
      backgroundColor: colors.surface,
      backgroundBorderColor: colors.outlineVariant,
    );

    return Container(
      width: double.infinity,
      height: chartLayout.height,
      padding: EdgeInsets.symmetric(
        horizontal: chartLayout.contentPaddingHorizontal,
        vertical: chartLayout.contentPaddingVertical,
      ),
      decoration: BoxDecoration(
        color: chartLayout.backgroundColor,
        borderRadius: BorderRadius.circular(chartLayout.backgroundRadius),
        border: Border.all(color: chartLayout.backgroundBorderColor),
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
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double availableWidth = constraints.maxWidth;
                const double barCount = 10;
                final double effectiveGap = chartLayout.barGap;
                final double totalGap = effectiveGap * (barCount - 1);
                final double barWidth = ((availableWidth - totalGap) / barCount).clamp(2.0, double.infinity);

                final double labelHeight = 12;
                // Reverse values so bars display 10 → 1 (left to right)
                final List<int> reversed = List<int>.from(values.reversed);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: CustomPaint(
                        size: Size(availableWidth, (constraints.maxHeight - labelHeight).clamp(0, double.infinity)),
                        painter: _CommentBarPainter(
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
                    // X-axis labels (10 → 1)
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

    final String? date = _readString(data['date']);
    if (date != null && date.isNotEmpty) {
      chips.add(_buildChip(colors, date));
    }

    final String? platform = _readString(data['platform']);
    if (platform != null && platform.isNotEmpty) {
      chips.add(_buildChip(colors, platform));
    }

    final int? totalEps = _readInt(data['total_episodes']) ?? _readInt(data['eps']);
    if (totalEps != null && totalEps > 0) {
      chips.add(_buildChip(colors, '共 $totalEps 话'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: chips,
      ),
    );
  }

  Widget _buildChip(ColorScheme colors, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: colors.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildGenreTags(ColorScheme colors, List<dynamic> tags) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: tags.whereType<String>().map((String tag) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 11,
                color: colors.onTertiaryContainer,
              ),
            ),
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
        final String key = _readString(entry['key']) ?? '';
        final dynamic rawValue = entry['value'];
        String value;
        if (rawValue is List) {
          value = rawValue.whereType<String>().join('、');
        } else {
          value = _readString(rawValue) ?? '';
        }
        if (key.isNotEmpty && value.isNotEmpty) {
          entries.add(MapEntry<String, String>(key, value));
        }
      }
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    final List<MapEntry<String, String>> display = entries.take(6).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: display.map((MapEntry<String, String> e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 80,
                  child: Text(
                    '${e.key}:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    e.value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
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
            Text(
              '简介',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 20,
              height: 20,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 14,
                icon: const Icon(Icons.copy),
                tooltip: '复制简介',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: summary));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('简介已复制'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedCrossFade(
          firstChild: Text(
            summary,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          secondChild: Text(
            summary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          crossFadeState: _summaryExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        if (summary.length > 120)
          TextButton(
            onPressed: () {
              setState(() {
                _summaryExpanded = !_summaryExpanded;
              });
            },
            child: Text(_summaryExpanded ? '收起' : '展开'),
          ),
      ],
    );
  }

  Widget _buildActionButton(ColorScheme colors) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).pop();
          widget.onOpenInBrowser();
        },
        icon: const Icon(Icons.open_in_browser),
        label: const Text('在浏览器中打开 Bangumi 条目'),
      ),
    );
  }

  // ---- Helper methods ----

  String? _readString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final double? parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }
}
