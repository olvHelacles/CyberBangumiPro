/// 全局常量
/// ─────────────────────────────────────────────

/// Current app version, kept in sync with pubspec.yaml.
const String appVersion = '0.7.1';

// URLs
const String bgmlistArchiveBaseUrl = 'https://bgmlist.com/archive';
const String bangumiApiBaseUrl = 'https://api.bgm.tv';
const String bgmListOnAirApiUrl = 'https://bgmlist.com/api/v1/bangumi/onair';

// Storage keys
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
const String correctionBaseStorageKey = 'correction_base_v1';
const String catchUpProgressStorageKey = 'catch_up_progress_v1';
const String catchUpTotalEpsStorageKey = 'catch_up_total_eps_v1';
const String catchUpTitlesStorageKey = 'catch_up_titles_v1';
const String watchlistLastUpdatedStorageKey = 'watchlist_last_updated_v1';
const String watchlistLastAiredEpStorageKey = 'watchlist_last_aired_ep_v1';
const String timezoneConversionEnabledSettingKey =
    'timezone_conversion_enabled';
const String timezoneOffsetMinutesSettingKey = 'timezone_offset_minutes';
const String proxyEnabledSettingKey = 'proxy_enabled';
const String proxyHostSettingKey = 'proxy_host';
const String proxyPortSettingKey = 'proxy_port';
const String proxySubscriptionUrlSettingKey = 'proxy_subscription_url';
const String proxyBypassSettingKey = 'proxy_bypass';

// User-Agents
const String appUserAgent = 'olvHelacles/CyberBangumiPro/$appVersion (https://github.com/olvHelacles/CyberBangumiPro)';
const String browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

// HTTP headers
const Map<String, String> requestHeaders = <String, String>{
  'User-Agent': browserUserAgent,
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
};

const Map<String, String> imageRequestHeaders = <String, String>{
  'Referer': 'https://bangumi.tv/',
  'User-Agent': browserUserAgent,
};

// Font fallbacks
const List<String> sansFallbacks = <String>[
  'Microsoft YaHei',
  'Microsoft YaHei UI',
  'PingFang SC',
  'Noto Sans CJK SC',
  'Noto Sans SC',
];

// Default settings
const int defaultSettingProgressConcurrency = 10;
const int defaultSettingCoverCacheConcurrency = 12;
const bool defaultSettingTimezoneConversionEnabled = true;
const int defaultSettingTimezoneOffsetMinutes = 8 * 60;
const bool defaultSettingProxyEnabled = true;
const String defaultSettingProxyHost = '127.0.0.1';
const int defaultSettingProxyPort = 7890;
const String defaultSettingProxyBypass = 'localhost,127.0.0.1';
const String defaultSettingProxySubscriptionUrl = '';

// Weekday names
const Map<int, String> weekdayMap = <int, String>{
  1: '星期一',
  2: '星期二',
  3: '星期三',
  4: '星期四',
  5: '星期五',
  6: '星期六',
  7: '星期日',
};

/// Ordered weekday list (Monday → Sunday)
const List<String> orderedWeekdays = <String>[
  '星期一',
  '星期二',
  '星期三',
  '星期四',
  '星期五',
  '星期六',
  '星期日',
];

/// Wraps a weekday index (1-7) so that shifting by N days never leaves [1,7].
int wrapWeekday(int value) {
  return positiveMod(value - 1, 7) + 1;
}

/// Positive modulo that always returns a non-negative result.
int positiveMod(int value, int modulo) {
  final int result = value % modulo;
  return result < 0 ? result + modulo : result;
}

/// Floor division that rounds toward negative infinity.
int floorDiv(int value, int divisor) {
  if (divisor == 0) {
    throw ArgumentError('divisor cannot be zero');
  }
  final int positiveDivisor = divisor < 0 ? -divisor : divisor;
  if (value >= 0) {
    return value ~/ positiveDivisor;
  }
  return -(((-value) + positiveDivisor - 1) ~/ positiveDivisor);
}

/// Read trimmed string from dynamic, returning empty string for null/"null".
String readJsonString(dynamic value) {
  if (value == null) {
    return '';
  }
  final String text = value.toString().trim();
  return text == 'null' ? '' : text;
}

/// Read a nullable string from dynamic, returning null for null/non-string input.
String? readJsonStringNullable(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// Read an int from dynamic (handles int, double, String).
int? readJsonInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString().trim());
}

/// Read a double from dynamic (handles double, int, String).
double? readJsonDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

/// Parse a "HH:MM" time string into total minutes since midnight, returning
/// a sentinel past 24:00 for invalid / unrecognized formats.
int parseUpdateTimeMinutes(String text) {
  final RegExpMatch? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (match == null) return 24 * 60 + 1;
  final int hour = int.tryParse(match.group(1) ?? '') ?? 99;
  final int minute = int.tryParse(match.group(2) ?? '') ?? 99;
  if (hour < 0 || hour > 29 || minute < 0 || minute > 59) return 24 * 60 + 1;
  return hour * 60 + minute;
}
