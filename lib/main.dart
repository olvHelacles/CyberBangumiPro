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
import 'widgets/progress_overlay.dart';
import 'widgets/subject_detail_sheet.dart';
import 'widgets/today_tab.dart';
import 'widgets/watch_tab.dart';
import 'widgets/week_calendar_tab.dart';
import 'widgets/search_tab.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/app_bar_remote_image.dart';
import 'widgets/debug_tools.dart';

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
      titleTextStyle:
          _styleWithWeight(baseTextTheme.titleLarge, FontWeight.w500).copyWith(
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
    debugPrint('[CyberBangumi] Clash 启动失败: $e');
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
  static const int _maxDebugLogEntries = 400;

  List<DaySchedule> _scheduleData = <DaySchedule>[];
  List<SubjectItem> _allItems = <SubjectItem>[];
  List<SubjectItem> _todayItems = <SubjectItem>[];
  List<SubjectItem> _watchlist = <SubjectItem>[];

  // Indices for O(1) lookups in applyRealtimeUpdate.
  Map<String, int> _allItemsIndex = <String, int>{};
  Map<String, int> _todayItemsIndex = <String, int>{};
  Map<String, int> _watchlistIndex = <String, int>{};
  Map<String, Map<String, int>> _scheduleDataIndex =
      <String, Map<String, int>>{};
  final Map<String, SubjectProgress> _progressCache =
      <String, SubjectProgress>{};
  final Map<String, SubjectProgress> _rawProgressCache =
      <String, SubjectProgress>{};
  final Map<String, int> _legacyAbsoluteProgressCorrections = <String, int>{};
  bool _progressCorrectionMigrationDirty = false;
  Map<String, int> _manualProgressCorrections = <String, int>{};
  Map<String, int> _correctionBaseTheoretical = <String, int>{};
  Map<String, int> _catchUpProgress = <String, int>{};
  Map<String, int> _catchUpTotalEps = <String, int>{};
  Map<String, DateTime> _watchlistLastUpdated = <String, DateTime>{};
  Map<String, int> _watchlistLastAiredEp = <String, int>{};
  Timer? _periodicCheckTimer;
  Map<String, Map<int, String>> _catchUpTitles = <String, Map<int, String>>{};
  Set<String> _selectedIds = <String>{};
  int? _debugWeekdayOverride;

  String get _systemWeekday {
    final DateTime now = DateTime.now().toUtc().add(
      Duration(minutes: _effectiveDisplayTimezoneOffsetMinutes),
    );
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
    _periodicCheckTimer?.cancel();
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
    final String? startupError = ClashManager.instance.startupError;
    if (startupError != null && startupError.isNotEmpty) {
      _appendDebugLog('代理: 启动阶段异常: $startupError');
    }
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
    _startPeriodicCheck();
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
    _periodicCheckTimer?.cancel();
    _startPeriodicCheck();
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

  String get _currentTimezoneFullLabel => _settingTimezoneConversionEnabled
      ? BroadcastTimeConverter.formatUtcOffsetLabel(
          _settingTimezoneOffsetMinutes,
        )
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
        if (day.weekday.trim().isNotEmpty &&
            item.updateTime.trim().isNotEmpty) {
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

        grouped
            .putIfAbsent(weekday, () => <SubjectItem>[])
            .add(item.copyWith(updateTime: time));
      }
    }

    final List<DaySchedule> converted = <DaySchedule>[];
    for (final String day in orderedWeekdays) {
      converted.add(
        DaySchedule(weekday: day, items: grouped[day] ?? <SubjectItem>[]),
      );
      grouped.remove(day);
    }
    grouped.forEach((String day, List<SubjectItem> items) {
      converted.add(DaySchedule(weekday: day, items: items));
    });
    return converted;
  }

  Future<void> _loadSettings() async {
    final Map<String, dynamic> state = await _appStateStore.readState();
    final String raw = jsonEncode(
      state[settingsStorageKey] ?? <String, dynamic>{},
    );
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
    _settingApiUserAgent =
        (jsonMap['api_user_agent'] as String? ?? appUserAgent).trim();
    // Migrate legacy hardcoded UA to the new format.
    if (_settingApiUserAgent == 'OlvSilence/my-private-project') {
      _settingApiUserAgent = appUserAgent;
    }
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
        (jsonMap[proxyEnabledSettingKey] as bool?) ??
        defaultSettingProxyEnabled;
    _settingProxyHost =
        (jsonMap[proxyHostSettingKey] as String? ?? defaultSettingProxyHost)
            .trim();
    _settingProxyPort =
        (jsonMap[proxyPortSettingKey] as num?)?.toInt() ??
        defaultSettingProxyPort;
    _settingProxyBypass =
        (jsonMap[proxyBypassSettingKey] as String? ?? defaultSettingProxyBypass)
            .trim();
    _settingProxySubscriptionUrl =
        (jsonMap[proxySubscriptionUrlSettingKey] as String? ??
                defaultSettingProxySubscriptionUrl)
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

    // Load correction base theoretical values.
    final String baseRaw = jsonEncode(
      state[correctionBaseStorageKey] ?? <String, dynamic>{},
    );
    final Map<String, int> bases = <String, int>{};
    try {
      final dynamic decodedBase = jsonDecode(baseRaw);
      if (decodedBase is Map<String, dynamic>) {
        decodedBase.forEach((String key, dynamic value) {
          final int? parsed = (value as num?)?.toInt();
          if (key.isNotEmpty && parsed != null) {
            bases[key] = parsed;
          }
        });
      }
    } catch (_) {}
    _correctionBaseTheoretical = bases;

    // Load catch-up progress.
    final String catchUpRaw = jsonEncode(
      state[catchUpProgressStorageKey] ?? <String, dynamic>{},
    );
    final Map<String, int> catchUp = <String, int>{};
    try {
      final dynamic decodedCatchUp = jsonDecode(catchUpRaw);
      if (decodedCatchUp is Map<String, dynamic>) {
        decodedCatchUp.forEach((String key, dynamic value) {
          final int? parsed = (value as num?)?.toInt();
          if (key.isNotEmpty && parsed != null && parsed > 0) {
            catchUp[key] = parsed;
          }
        });
      }
    } catch (_) {}
    _catchUpProgress = catchUp;

    // Load catch-up total episodes.
    final String totalRaw = jsonEncode(
      state[catchUpTotalEpsStorageKey] ?? <String, dynamic>{},
    );
    final Map<String, int> totalEps = <String, int>{};
    try {
      final dynamic decodedTotal = jsonDecode(totalRaw);
      if (decodedTotal is Map<String, dynamic>) {
        decodedTotal.forEach((String key, dynamic value) {
          final int? parsed = (value as num?)?.toInt();
          if (key.isNotEmpty && parsed != null && parsed > 0) {
            totalEps[key] = parsed;
          }
        });
      }
    } catch (_) {}
    _catchUpTotalEps = totalEps;

    // Load catch-up episode titles.
    final String titlesRaw = jsonEncode(
      state[catchUpTitlesStorageKey] ?? <String, dynamic>{},
    );
    final Map<String, Map<int, String>> titles = <String, Map<int, String>>{};
    try {
      final dynamic decodedTitles = jsonDecode(titlesRaw);
      if (decodedTitles is Map<String, dynamic>) {
        decodedTitles.forEach((String sid, dynamic entry) {
          if (entry is Map<String, dynamic>) {
            final Map<int, String> epMap = <int, String>{};
            entry.forEach((String epStr, dynamic title) {
              final int? ep = int.tryParse(epStr);
              if (ep != null && title is String && title.isNotEmpty) {
                epMap[ep] = title;
              }
            });
            if (epMap.isNotEmpty) titles[sid] = epMap;
          }
        });
      }
    } catch (_) {}
    _catchUpTitles = titles;

    // Load catch-up last-modified timestamps.
    final String lastModRaw = jsonEncode(
      state[watchlistLastUpdatedStorageKey] ?? <String, dynamic>{},
    );
    final Map<String, DateTime> lastMod = <String, DateTime>{};
    try {
      final dynamic decodedLastMod = jsonDecode(lastModRaw);
      if (decodedLastMod is Map<String, dynamic>) {
        decodedLastMod.forEach((String sid, dynamic value) {
          if (sid.isNotEmpty && value is String) {
            final DateTime? parsed = DateTime.tryParse(value);
            if (parsed != null) lastMod[sid] = parsed;
          }
        });
      }
    } catch (_) {}
    _watchlistLastUpdated = lastMod;

    // Load watchlist last-aired-ep baseline (for sort-timestamp decisions).
    final String lastAiredRaw = jsonEncode(
      state[watchlistLastAiredEpStorageKey] ?? <String, dynamic>{},
    );
    final Map<String, int> lastAired = <String, int>{};
    try {
      final dynamic decodedLastAired = jsonDecode(lastAiredRaw);
      if (decodedLastAired is Map<String, dynamic>) {
        decodedLastAired.forEach((String sid, dynamic value) {
          final int? parsed = (value as num?)?.toInt();
          if (sid.isNotEmpty && parsed != null && parsed > 0) {
            lastAired[sid] = parsed;
          }
        });
      }
    } catch (_) {}
    _watchlistLastAiredEp = lastAired;
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
    state[correctionBaseStorageKey] = _correctionBaseTheoretical;
    state[catchUpProgressStorageKey] = _catchUpProgress;
    state[catchUpTotalEpsStorageKey] = _catchUpTotalEps;
    // Convert int-keyed map to string-keyed for JSON serialization.
    state[catchUpTitlesStorageKey] = _catchUpTitles.map(
      (String sid, Map<int, String> epMap) => MapEntry<String, dynamic>(
        sid,
        epMap.map((int ep, String title) => MapEntry<String, dynamic>(
          ep.toString(), title,
        )),
      ),
    );
    state[watchlistLastUpdatedStorageKey] = _watchlistLastUpdated.map(
      (String sid, DateTime dt) => MapEntry<String, dynamic>(
        sid, dt.toIso8601String(),
      ),
    );
    state[watchlistLastAiredEpStorageKey] =
        Map<String, dynamic>.from(_watchlistLastAiredEp);
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

  SubjectProgress _applyCorrection(SubjectProgress progress, int corrected) {
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

    // Auto-clear correction if the theoretical value has changed since the
    // correction was saved (i.e. new episodes have aired).
    final int? baseTheoretical = _correctionBaseTheoretical[subjectId];
    if (baseTheoretical != null) {
      final int currentTheoretical = _resolveTheoreticalAiredEp(progress);
      if (currentTheoretical != baseTheoretical) {
        _manualProgressCorrections.remove(subjectId);
        _correctionBaseTheoretical.remove(subjectId);
      }
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
    final List<int> commonTimezoneOffsets = <int>[
      for (int hour = -12; hour <= 14; hour++) hour * 60,
    ];

    unawaited(ClashManager.instance.refreshNodeInfo());

    final SettingsData? result = await showDialog<SettingsData>(
      context: context,
      builder: (BuildContext context) {
        return SettingsDialog(
          initialData: SettingsData(
            progressConcurrency: _settingProgressConcurrency,
            coverCacheConcurrency: _settingCoverCacheConcurrency,
            apiUserAgent: _settingApiUserAgent,
            themeMode: _settingThemeMode,
            appBarBackgroundImageEnabled: _settingAppBarBackgroundImageEnabled,
            appBarBackgroundImagePath: _settingAppBarBackgroundImagePath,
            timezoneConversionEnabled: _settingTimezoneConversionEnabled,
            timezoneOffsetMinutes: _settingTimezoneOffsetMinutes,
            proxyEnabled: _settingProxyEnabled,
            proxySubscriptionUrl: _settingProxySubscriptionUrl,
          ),
          commonTimezoneOffsets: commonTimezoneOffsets,
          currentVersion: appVersion,
          onOpenWatchArchive: () {
            Navigator.of(context).pop();
            _openWatchArchiveDialog();
          },
          onClearCoverCache: () => _clearCoverCache(),
        );
      },
    );

    if (result == null || !mounted) return;

    final bool themeModeChanged = _settingThemeMode != result.themeMode;
    final bool timezoneChanged =
        _settingTimezoneConversionEnabled != result.timezoneConversionEnabled ||
        _settingTimezoneOffsetMinutes != result.timezoneOffsetMinutes;
    final bool proxyChanged = _settingProxyEnabled != result.proxyEnabled;
    final bool subscriptionChanged =
        _settingProxySubscriptionUrl != result.proxySubscriptionUrl;

    setState(() {
      _settingProgressConcurrency = result.progressConcurrency;
      _settingCoverCacheConcurrency = result.coverCacheConcurrency;
      _settingApiUserAgent = result.apiUserAgent;
      _settingThemeMode = result.themeMode;
      _settingAppBarBackgroundImageEnabled =
          result.appBarBackgroundImageEnabled;
      _settingAppBarBackgroundImagePath = result.appBarBackgroundImagePath;
      _settingTimezoneConversionEnabled = result.timezoneConversionEnabled;
      _settingTimezoneOffsetMinutes = result.timezoneOffsetMinutes;
      _settingProxyEnabled = result.proxyEnabled;
      _settingProxyHost = defaultSettingProxyHost;
      _settingProxyPort = defaultSettingProxyPort;
      _settingProxyBypass = defaultSettingProxyBypass;
      _settingProxySubscriptionUrl = result.proxySubscriptionUrl;
    });

    if (themeModeChanged) {
      widget.onThemeModeChanged?.call(_settingThemeMode);
    }
    if (proxyChanged) {
      _service.updateProxySettings(
        _settingProxyEnabled,
        _settingProxyHost,
        _settingProxyPort,
        _settingProxyBypass,
      );
    }
    if (result.proxySubscriptionUrl.isNotEmpty && subscriptionChanged) {
      try {
        await ClashManager.instance.stop();
        await ClashManager.instance.applySubscription(
          result.proxySubscriptionUrl,
        );
        await ClashManager.instance.start();
      } catch (_) {}
    }
    await _saveSettings();
    if (timezoneChanged) {
      await _refreshCalendarSchedule(forceNetwork: true);
      await _refreshProgressFromMainAction();
    }
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
                    separatorBuilder: (BuildContext context, int index) =>
                        const Divider(height: 1),
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
    final String savedMonth = (state[calendarAutoRefreshMonthKey] ?? '')
        .toString();
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

  void _rebuildAllIndices() {
    _allItemsIndex = <String, int>{
      for (int i = 0; i < _allItems.length; i++)
        if (_allItems[i].subjectId.isNotEmpty) _allItems[i].subjectId: i,
    };
    _todayItemsIndex = <String, int>{
      for (int i = 0; i < _todayItems.length; i++)
        if (_todayItems[i].subjectId.isNotEmpty) _todayItems[i].subjectId: i,
    };
    _watchlistIndex = <String, int>{
      for (int i = 0; i < _watchlist.length; i++)
        if (_watchlist[i].subjectId.isNotEmpty) _watchlist[i].subjectId: i,
    };
    _scheduleDataIndex = <String, Map<String, int>>{
      for (int d = 0; d < _scheduleData.length; d++)
        _scheduleData[d].weekday: <String, int>{
          for (int j = 0; j < _scheduleData[d].items.length; j++)
            if (_scheduleData[d].items[j].subjectId.isNotEmpty)
              _scheduleData[d].items[j].subjectId: j,
        },
    };
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
      _rebuildAllIndices();
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
              '星期日',
              '星期一',
              '星期二',
              '星期三',
              '星期四',
              '星期五',
              '星期六',
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
      final DateTime oneYearAgo = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 9))
          .subtract(const Duration(days: 365));
      final List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[];

      for (final dynamic raw in itemsRaw) {
        if (raw is! Map<String, dynamic>) continue;
        final String beginStr = rs(raw['begin']);
        final DateTime? begin = rd(beginStr);
        if (begin == null || begin.isBefore(oneYearAgo)) continue;

        // Extract bangumi id.
        final String bgmId = _service.extractBangumiIdFromBgmListItem(raw);
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
        workers.add(
          Future<void>(() async {
            while (true) {
              final int idx;
              idx = nextIdx;
              nextIdx++;
              if (idx >= candidates.length) return;
              final String id = candidates[idx]['id'] as String;
              try {
                if (await _service.isSubjectStillAiring(id)) {
                  stillAiring.add(id);
                  _appendDebugLog(
                    '日历: OnAir 补充收录 $id (${candidates[idx]['title']})',
                  );
                }
              } catch (_) {}
            }
          }),
        );
      }
      await Future.wait(workers);

      // 6. For still-airing candidates, look up their broadcast day/time from
      //    the onair JSON and add them to the schedule.
      for (final dynamic raw in itemsRaw) {
        if (raw is! Map<String, dynamic>) continue;
        final String bgmId = _service.extractBangumiIdFromBgmListItem(raw);
        if (!stillAiring.contains(bgmId)) continue;

        // Broadcast time from the onair JSON.
        final String broadcast = rs(raw['broadcast']);
        String weekday = '';
        String updateTime = '';
        if (broadcast.isNotEmpty) {
          final RegExpMatch? m = RegExp(
            r'^R/([^/]+)/P(\d+)D$',
          ).firstMatch(broadcast);
          if (m != null) {
            final DateTime? start = parseJst(m.group(1)!);
            if (start != null) {
              final int wd = start.weekday;
              const List<String> wds = <String>[
                '星期一',
                '星期二',
                '星期三',
                '星期四',
                '星期五',
                '星期六',
                '星期日',
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
              if (t.isNotEmpty) {
                cnName = t;
                break;
              }
            }
          }
        }
        enriched[weekday]!.add(
          SubjectItem(
            subjectId: bgmId,
            subjectUrl: 'https://bangumi.tv/subject/$bgmId',
            nameCn: cnName,
            nameOrigin: jpName,
            coverUrl: '',
            updateTime: updateTime,
          ),
        );
      }

      // 7. Rebuild schedule in weekday order.
      final List<DaySchedule> result = <DaySchedule>[];
      for (final String w in <String>[
        '星期一',
        '星期二',
        '星期三',
        '星期四',
        '星期五',
        '星期六',
        '星期日',
      ]) {
        final List<SubjectItem> items = enriched[w]!;
        if (items.isEmpty) continue;
        items.sort(
          (SubjectItem a, SubjectItem b) =>
              a.updateTime.compareTo(b.updateTime),
        );
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
        // Restore subject start dates from cache (used to filter today items).
        final Map<String, DateTime> cachedStartDates =
            await _calendarCacheManager.loadStartDates();
        if (_service.subjectStartDates.isEmpty && cachedStartDates.isNotEmpty) {
          _service.seedSubjectStartDates(cachedStartDates);
        }
        if (cachedSchedule.isNotEmpty) {
          if (!mounted) {
            return;
          }
          _applyScheduleData(
            cachedSchedule,
            doneStatusText: initial ? '已从本地缓存加载日历' : '日历已从本地缓存刷新',
          );
          unawaited(_hydrateCachedCoversForTodayItems());
          unawaited(_hydrateCachedCoversForWatchlistItems());
          return;
        }
      }

      if (!cacheTimezoneMatched) {
        _appendDebugLog('日历缓存时区不匹配，跳过缓存并重新抓取');
      }

      final List<DaySchedule> mergedScheduleJst = await _service
          .fetchCalendarSchedule();
      final List<DaySchedule> enrichedJst = await _enrichWithOnAirShows(
        mergedScheduleJst,
      );
      final int enrichedCount =
          enrichedJst.fold<int>(
            0,
            (int sum, DaySchedule day) => sum + day.items.length,
          ) -
          mergedScheduleJst.fold<int>(
            0,
            (int sum, DaySchedule day) => sum + day.items.length,
          );
      if (enrichedCount > 0) {
        _appendDebugLog('日历: OnAir 补充后共计 $enrichedCount 部');
      }
      final List<DaySchedule> mergedSchedule =
          _convertScheduleFromJstForDisplay(enrichedJst);
      await _calendarCacheManager.saveWithStartDates(
        mergedSchedule, _service.subjectStartDates);
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
        // Restore start dates even on fallback path.
        final Map<String, DateTime> fallbackStartDates =
            await _calendarCacheManager.loadStartDates();
        if (_service.subjectStartDates.isEmpty && fallbackStartDates.isNotEmpty) {
          _service.seedSubjectStartDates(fallbackStartDates);
        }
        if (cachedSchedule.isNotEmpty) {
          if (!mounted) {
            return;
          }
          _applyScheduleData(cachedSchedule, doneStatusText: '网络失败，已回退本地缓存日历');
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

  Future<void> _openDebugToolsDialog() async {
    // Delegate to DebugTools widget.
    await DebugTools.showTools(
      context: context,
      debugLogs: _debugLogs,
      debugWeekdayOverride: _debugWeekdayOverride,
      debugShowChartHoverHitArea: _debugShowChartHoverHitArea,
      systemWeekday: _systemWeekday,
      watchlist: _watchlist,
      watchArchiveStore: _watchArchiveStore,
      currentQuarterLabel: _currentQuarterLabel(),
      onApplyWeekdayOverride: (int? weekday) {
        setState(() {
          _debugWeekdayOverride = weekday;
          _todayItems = _resolveTodayItemsFromSchedule(_scheduleData);
          _rebuildAllIndices();
        });
        _showStatus(
          weekday == null ? '已切换为系统时间' : '已调试指定今日为 ${weekdayMap[weekday]}',
        );
        unawaited(_hydrateCachedCoversForTodayItems());
      },
      onClearLogs: () {
        setState(() {
          _debugLogs.clear();
        });
      },
      onArchiveWatchlist: () {
        final List<SubjectItem> targets = _watchlist
            .where((SubjectItem item) => item.subjectId.isNotEmpty)
            .toList();
        if (targets.isEmpty) {
          _showStatus('调试归档：当前没有可归档的关注番剧');
          return;
        }
        final String quarter = _currentQuarterLabel();
        unawaited(
          _watchArchiveStore.appendEntries(
            targets
                .map(
                  (SubjectItem item) =>
                      WatchArchiveEntry.fromSubject(item, quarter: quarter),
                )
                .toList(),
          ),
        );
        _showStatus('调试归档完成：已加入 ${targets.length} 部番剧');
      },
      onToggleHoverHitArea: () {
        setState(() {
          _debugShowChartHoverHitArea = !_debugShowChartHoverHitArea;
        });
      },
      showStatus: (String msg) => _showStatus(msg),
      appendDebugLog: (String msg) => _appendDebugLog(msg),
      openLogDialog: () async {
        final String logText = _debugLogs.isEmpty
            ? '暂无日志输出。'
            : _debugLogs.join('\n');
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('调试日志窗口'),
              content: SizedBox(
                width: 760,
                height: 460,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
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
                    });
                    _appendDebugLog('日志已手动清空');
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
      },
      openWeekdayDialog: () async {
        final int? selected = await showDialog<int?>(
          context: context,
          builder: (BuildContext context) {
            int? tempValue = _debugWeekdayOverride;
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setLocalState) {
                return AlertDialog(
                  title: const Text('调试：指定今日星期'),
                  content: SizedBox(
                    width: 320,
                    child: DropdownButtonFormField<int?>(
                      initialValue: tempValue,
                      decoration: const InputDecoration(
                        labelText: '程序中”今日”对应星期',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<int?>>[
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text('系统时间（当前：$_systemWeekday）'),
                        ),
                        for (int i = 1; i <= 7; i++)
                          DropdownMenuItem<int?>(
                            value: i,
                            child: Text(weekdayMap[i] ?? '星期$i'),
                          ),
                      ],
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
        if (selected != _debugWeekdayOverride) {
          setState(() {
            _debugWeekdayOverride = selected;
            _todayItems = _resolveTodayItemsFromSchedule(_scheduleData);
            _rebuildAllIndices();
          });
          _showStatus(
            selected == null ? '已切换为系统时间' : '已调试指定今日为 ${weekdayMap[selected]}',
          );
          unawaited(_hydrateCachedCoversForTodayItems());
        }
      },
    );
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
      _rebuildAllIndices();
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
      _rebuildAllIndices();
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
      _rebuildAllIndices();
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
        final int? allIdx = _allItemsIndex[fresh.subjectId];
        if (allIdx != null) {
          final SubjectItem prev = _allItems[allIdx];
          _allItems[allIdx] = prev.copyWith(
            coverUrl: fresh.coverUrl.isNotEmpty
                ? fresh.coverUrl
                : prev.coverUrl,
            localCoverPath: fresh.localCoverPath.isNotEmpty
                ? fresh.localCoverPath
                : prev.localCoverPath,
          );
        }

        final int? todayIdx = _todayItemsIndex[fresh.subjectId];
        if (todayIdx != null) {
          final SubjectItem prev = _todayItems[todayIdx];
          _todayItems[todayIdx] = prev.copyWith(
            coverUrl: fresh.coverUrl.isNotEmpty
                ? fresh.coverUrl
                : prev.coverUrl,
            localCoverPath: fresh.localCoverPath.isNotEmpty
                ? fresh.localCoverPath
                : prev.localCoverPath,
          );
        }

        final int? watchIdx = _watchlistIndex[fresh.subjectId];
        if (watchIdx != null) {
          final SubjectItem prev = _watchlist[watchIdx];
          _watchlist[watchIdx] = prev.copyWith(
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

        for (int d = 0; d < _scheduleData.length; d++) {
          final String wk = _scheduleData[d].weekday;
          final int? idx = _scheduleDataIndex[wk]?[fresh.subjectId];
          if (idx != null) {
            final List<SubjectItem> items =
                List<SubjectItem>.from(_scheduleData[d].items);
            final SubjectItem prev = items[idx];
            items[idx] = prev.copyWith(
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
            _scheduleData[d] = DaySchedule(weekday: wk, items: items);
            break;
          }
        }
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
      _rebuildAllIndices();
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
    // Build a set of IDs that are in the current calendar.
    final Set<String> calendarIds = <String>{};
    for (final DaySchedule day in _scheduleData) {
      for (final SubjectItem citem in day.items) {
        if (citem.subjectId.isNotEmpty) calendarIds.add(citem.subjectId);
      }
    }
    for (final SubjectItem item in _watchlist) {
      if (item.subjectId.isEmpty) {
        continue;
      }
      if (allowedIds != null && !allowedIds.contains(item.subjectId)) {
        continue;
      }
      // Skip items not in the current calendar (completed/补番) unless explicitly requested.
      if (allowedIds == null && !calendarIds.contains(item.subjectId)) {
        // 补番条目：仍然加入 targets，processOne 会走轻量路径（仅抓评分）
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
        final bool isCatchUp = !calendarIds.contains(sid);
        if (isCatchUp) {
          // 补番条目：仅抓评分，不拉分集/评论
          try {
            final Map<String, dynamic>? subject =
                await _service.fetchSubjectFromApi(sid);
            if (subject != null) {
              final dynamic ratingRaw = subject['rating'];
              double? ratingScore;
              if (ratingRaw is Map<String, dynamic>) {
                ratingScore = readJsonDouble(ratingRaw['score']);
              }
              final int? totalEps = readJsonInt(subject['total_episodes']) ??
                  readJsonInt(subject['eps']);
              rawProgress = SubjectProgress(
                ratingScore: ratingScore,
                totalEpsDeclared: totalEps,
                progressText:
                    totalEps != null ? '?/$totalEps' : null,
              );
            } else {
              rawProgress = const SubjectProgress(error: '获取条目信息失败');
            }
          } catch (e) {
            _appendDebugLog('网络: 抓取失败[补番评分] $sid ($e)');
            rawProgress = SubjectProgress(error: e.toString());
          }
        } else {
          try {
            _appendDebugLog('网络: 开始抓取[进度] ${item.subjectUrl} (subjectId=$sid)');
            final BroadcastScheduleHint? hint = scheduleHintsBySubjectId[sid];
            rawProgress = await _service.fetchSubjectProgress(
              item.subjectUrl,
              scheduleTime: hint?.time ?? '',
              scheduleWeekday: hint?.weekday ?? '',
              displayTimezoneOffsetMinutes:
                  _effectiveDisplayTimezoneOffsetMinutes,
            );
          } catch (e) {
            _appendDebugLog('网络: 抓取失败[进度] ${item.subjectUrl} ($e)');
            rawProgress = SubjectProgress(error: e.toString());
          }
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

      // Capture old progress BEFORE setState overwrites the cache.
      final SubjectProgress? previousProgress = _rawProgressCache[sid];
      final int? previousAiredEp = _watchlistLastAiredEp[sid];

      setState(() {
        _rawProgressCache[sid] = rawProgress;
        _progressCache[sid] = progress;
        _progressRefreshDone = processed;
        // Only update sort timestamp when a new episode has aired.
        if (watchTargets.containsKey(sid)) {
          final int? newEp = rawProgress.latestAiredEp;
          final bool hasNewEpisode = newEp != null && newEp > 0 &&
              (previousProgress == null
                  ? (previousAiredEp != null && newEp > previousAiredEp)
                  : newEp > (previousProgress.latestAiredEp ?? 0));
          if (hasNewEpisode) {
            _watchlistLastUpdated[sid] = DateTime.now();
          }
          if (newEp != null && newEp > 0) {
            _watchlistLastAiredEp[sid] = newEp;
          }
        }
        // Cache total episodes for catch-up items so they survive restart.
        final int? totalEps = rawProgress.totalEpsDeclared ?? rawProgress.totalEpsListed;
        if (totalEps != null && totalEps > 0) {
          _catchUpTotalEps[sid] = totalEps;
        }
        // Cache episode titles for catch-up items so they survive restart.
        if (rawProgress.episodeTitleByEp.isNotEmpty) {
          _catchUpTitles[sid] = Map<int, String>.from(
            rawProgress.episodeTitleByEp,
          );
        }
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
    // Persist watchlist last-aired-ep baseline for next-launch sort decisions.
    await _saveProgressCorrections();

    setState(() {
      _isLoadingProgress = false;
      _progressRefreshDone = _progressRefreshTotal;
    });
    _showStatus('进度已更新');
  }

  void _startPeriodicCheck() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 120),
      (_) => _checkRecentlyAiredShows(),
    );
  }

  Future<void> _checkRecentlyAiredShows() async {
    if (_isLoadingProgress || _isLoadingSchedule) return;
    if (_scheduleData.isEmpty || _selectedIds.isEmpty) return;

    final DateTime now = DateTime.now();
    final int displayOffset = _effectiveDisplayTimezoneOffsetMinutes;
    final Set<String> toCheck = <String>{};

    for (final DaySchedule day in _scheduleData) {
      for (final SubjectItem item in day.items) {
        if (item.subjectId.isEmpty || item.updateTime.isEmpty) continue;
        if (!_selectedIds.contains(item.subjectId)) continue;

        final ConvertedWeekdayTime? ct =
            BroadcastTimeConverter.convertWeekdayAndTime(
          weekday: day.weekday,
          time: item.updateTime,
          fromOffsetMinutes: BroadcastTimeConverter.jstOffsetMinutes,
          toOffsetMinutes: displayOffset,
        );
        if (ct == null) continue;

        final int? wi = BroadcastTimeConverter.weekdayToIndex(ct.weekday);
        final int? minutes =
            BroadcastTimeConverter.parseClockMinutes(ct.time);
        if (wi == null || minutes == null) continue;

        DateTime broadcast = DateTime(
          now.year, now.month, now.day,
          minutes ~/ 60, minutes % 60,
        );
        final int diff = wi - now.weekday;
        if (diff != 0) {
          broadcast = broadcast.add(Duration(days: diff));
        }
        if (broadcast.isAfter(now)) continue;

        final int elapsed = now.difference(broadcast).inMinutes;
        if (elapsed >= 2 && elapsed <= 15) {
          toCheck.add(item.subjectId);
        }
      }
    }

    if (toCheck.isNotEmpty) {
      _refreshProgress(onlySubjectIds: toCheck);
    }
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
        return SubjectDetailSheet(
          subjectId: item.subjectId,
          item: item,
          service: _service,
          coverCacheManager: _coverCacheManager,
          isFollowed: _watchlist.any(
            (SubjectItem x) => x.subjectId == item.subjectId,
          ),
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
        await Process.start('cmd', <String>['/c', 'start', '', '"$url"']);
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

  Widget _buildAppBarBackgroundImage({required int? cacheWidth}) {
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
      return AppBarRemoteImage(
        key: ValueKey<String>(source),
        uri: uri,
        fit: _appBarBackgroundImageFit,
        cacheWidth: cacheWidth,
        fallback: (_) => buildFallback(),
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
        final double dpr = MediaQuery.of(
          context,
        ).devicePixelRatio.clamp(1.0, 3.0);
        final int? cacheWidth = constraints.maxWidth.isFinite
            ? math.max(1, (constraints.maxWidth * dpr).round())
            : null;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _buildAppBarBackgroundImage(cacheWidth: cacheWidth),
            ColoredBox(color: Colors.black.withValues(alpha: overlayAlpha)),
          ],
        );
      },
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
        _correctionBaseTheoretical.remove(item.subjectId);
        _legacyAbsoluteProgressCorrections.remove(item.subjectId);
        _progressCache.remove(item.subjectId);
        _rawProgressCache.remove(item.subjectId);
        _catchUpProgress.remove(item.subjectId);
        _catchUpTotalEps.remove(item.subjectId);
        _catchUpTitles.remove(item.subjectId);
        _watchlistLastUpdated.remove(item.subjectId);
        _rebuildAllIndices();
      });
      await _saveWatchlist();
      await _saveProgressCorrections();
      _showStatus('已取消关注：${item.displayName}');
      return;
    }

    setState(() {
      _watchlist = <SubjectItem>[..._watchlist, item];
      _selectedIds.add(item.subjectId);
      _rebuildAllIndices();
    });
    await _saveWatchlist();
    _showStatus('已关注：${item.displayName}');
    await _refreshProgress(onlySubjectIds: <String>{item.subjectId});
    await _saveProgressCorrections();
    // Hydrate cover immediately so it shows without waiting for calendar refresh.
    unawaited(_hydrateCachedCoversForWatchlistItems());
  }

  Future<void> _archiveWatchlistItem(SubjectItem item) async {
    if (item.subjectId.isEmpty) return;
    final String quarter = _currentQuarterLabel();
    await _watchArchiveStore.appendEntries(<WatchArchiveEntry>[
      WatchArchiveEntry.fromSubject(item, quarter: quarter),
    ]);
    if (!mounted) return;
    setState(() {
      _watchlist = _watchlist
          .where((SubjectItem x) => x.subjectId != item.subjectId)
          .toList();
      _selectedIds.remove(item.subjectId);
      _manualProgressCorrections.remove(item.subjectId);
      _legacyAbsoluteProgressCorrections.remove(item.subjectId);
      _progressCache.remove(item.subjectId);
      _rawProgressCache.remove(item.subjectId);
      _catchUpProgress.remove(item.subjectId);
      _catchUpTotalEps.remove(item.subjectId);
      _catchUpTitles.remove(item.subjectId);
      _watchlistLastUpdated.remove(item.subjectId);
      _rebuildAllIndices();
    });
    await _saveWatchlist();
    await _saveProgressCorrections();
    _showStatus('已归档：${item.displayName}');
  }

  void _onCatchUpForward(String subjectId) {
    final int totalEps = _progressCache[subjectId] != null
        ? (_progressCache[subjectId]!.totalEpsDeclared ??
            _progressCache[subjectId]!.totalEpsListed ??
            9999)
        : 9999;
    setState(() {
      final int current = _catchUpProgress[subjectId] ?? 0;
      if (current < totalEps) {
        _catchUpProgress[subjectId] = current + 1;
        _watchlistLastUpdated[subjectId] = DateTime.now();
      }
    });
    _saveProgressCorrections();
  }

  void _onCatchUpBack(String subjectId) {
    setState(() {
      final int current = _catchUpProgress[subjectId] ?? 0;
      if (current <= 1) {
        _catchUpProgress.remove(subjectId);
      } else {
        _catchUpProgress[subjectId] = current - 1;
      }
      _watchlistLastUpdated[subjectId] = DateTime.now();
    });
    _saveProgressCorrections();
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
            .clamp(0, 9999);
    final int theoreticalEp = _resolveTheoreticalAiredEp(
      baseProgress,
    ).clamp(0, totalEps);
    final int manualDelta =
        _manualProgressCorrections[subjectId] ??
        ((_legacyAbsoluteProgressCorrections[subjectId] ?? theoreticalEp) -
            theoreticalEp);
    int tempEp = (theoreticalEp + manualDelta).clamp(0, totalEps);

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
          _correctionBaseTheoretical.remove(subjectId);
          _legacyAbsoluteProgressCorrections.remove(subjectId);
        } else {
          _manualProgressCorrections[subjectId] = delta;
          _correctionBaseTheoretical[subjectId] = theoreticalEp;
          _legacyAbsoluteProgressCorrections.remove(subjectId);
        }
      } else {
        _manualProgressCorrections.remove(subjectId);
        _correctionBaseTheoretical.remove(subjectId);
        _legacyAbsoluteProgressCorrections.remove(subjectId);
      }

      final SubjectProgress? latest =
          _rawProgressCache[subjectId] ?? _progressCache[subjectId];
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

  @override
  /// 构建当前组件的界面结构。
  Widget build(BuildContext context) {
    final bool useCustomAppBarBackground = _shouldShowAppBarBackgroundImage();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          clipBehavior: Clip.hardEdge,
          backgroundColor: useCustomAppBarBackground
              ? Colors.transparent
              : null,
          surfaceTintColor: useCustomAppBarBackground
              ? Colors.transparent
              : null,
          flexibleSpace: useCustomAppBarBackground
              ? _buildAppBarFlexibleBackground()
              : null,
          title: const SizedBox.shrink(),
          bottom: _buildAppBarBottom(),
          actions: <Widget>[
            ProgressOverlay(
              compact: true,
              showStatusText: _showStatusText,
              statusText: _statusText,
              isCachingCalendarCovers: _isCachingCalendarCovers,
              calendarCoverCacheDone: _calendarCoverCacheDone,
              calendarCoverCacheTotal: _calendarCoverCacheTotal,
              isLoadingProgress: _isLoadingProgress,
              progressRefreshDone: _progressRefreshDone,
              progressRefreshTotal: _progressRefreshTotal,
            ),
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
                      TodayTab(
                        isLoadingSchedule: _isLoadingSchedule,
                        scheduleError: _scheduleError,
                        todayItems: _todayItems,
                        watchIds: _watchlist
                            .map((SubjectItem e) => e.subjectId)
                            .toSet(),
                        progressCache: _progressCache,
                        effectiveTodayWeekday: _effectiveTodayWeekday,
                        timezoneLabel: _currentTimezoneFullLabel,
                        onShowDetail: (SubjectItem item) =>
                            _showSubjectDetail(item),
                        onToggleFollow: (SubjectItem item) =>
                            _toggleWatchFromToday(item),
                      ),
                      WatchTab(
                        watchlist: _watchlist,
                        scheduleData: _scheduleData,
                        progressCache: _progressCache,
                        timezoneLabel: _currentTimezoneFullLabel,
                        calendarIds: _allItems.map((SubjectItem e) => e.subjectId).toSet(),
                        catchUpProgress: _catchUpProgress,
                        catchUpTotalEps: _catchUpTotalEps,
                        catchUpTitles: _catchUpTitles,
                        watchlistLastUpdated: _watchlistLastUpdated,
                        onShowDetail: (SubjectItem item) =>
                            _showSubjectDetail(item),
                        onToggleFollow: (SubjectItem item) =>
                            _toggleWatchFromToday(item),
                        onAdjustProgress: (SubjectItem item) =>
                            _openProgressAdjustDialog(item),
                        onArchive: (SubjectItem item) =>
                            _archiveWatchlistItem(item),
                        onCatchUpForward: (String id) => _onCatchUpForward(id),
                        onCatchUpBack: (String id) => _onCatchUpBack(id),
                      ),
                      WeekCalendarTab(
                        scheduleData: _scheduleData,
                        watchIds: _watchlist
                            .map((SubjectItem e) => e.subjectId)
                            .where((String id) => id.isNotEmpty)
                            .toSet(),
                        watchById: <String, SubjectItem>{
                          for (final SubjectItem item in _watchlist)
                            if (item.subjectId.isNotEmpty) item.subjectId: item,
                        },
                        showAll: _weekCalendarShowAll,
                        timezoneLabel: _currentTimezoneFullLabel,
                        onShowDetail: (SubjectItem item) =>
                            _showSubjectDetail(item),
                        onToggleFollow: (SubjectItem item) =>
                            _toggleWatchFromToday(item),
                        onShowAllChanged: (bool v) => setState(() {
                          _weekCalendarShowAll = v;
                        }),
                      ),
                      SearchTab(
                        service: _service,
                        coverCacheManager: _coverCacheManager,
                        watchIds: _watchlist
                            .map((SubjectItem e) => e.subjectId)
                            .where((String id) => id.isNotEmpty)
                            .toSet(),
                        coverCacheConcurrency: _settingCoverCacheConcurrency,
                        onShowDetail: (SubjectItem item) =>
                            _showSubjectDetail(item),
                        onToggleFollow: (SubjectItem item) =>
                            _toggleWatchFromToday(item),
                      ),
                    ],
                  ),
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
