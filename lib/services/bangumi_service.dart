import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../constants.dart';
import '../models/broadcast_types.dart';
import '../models/subject_item.dart';
import '../models/subject_progress.dart';

/// Cache entry for the isSubjectStillAiring check.
class _AiringCacheEntry {
  final bool result;
  final DateTime cachedAt;
  _AiringCacheEntry(this.result, this.cachedAt);
}

/// 统一网络服务层：日历抓取、Bangumi API 进度查询、封面获取
class BangumiService {
  BangumiService({http.Client? client})
    : _ownsClient = client == null,
      _proxyEnabled = false,
      _proxyHost = '127.0.0.1',
      _proxyPort = 7890,
      _proxyBypassList = const <String>['localhost', '127.0.0.1'],
      _subjectStartDates = <String, DateTime>{} {
    if (client != null) {
      _client = client;
      _insecureTlsClient = IOClient(_createHttpClient(allowBadCertificate: true));
    } else {
      final HttpClient normal = _createHttpClient();
      _applyProxy(normal);
      _client = IOClient(normal);
      final HttpClient insecure = _createHttpClient(allowBadCertificate: true);
      _applyProxy(insecure);
      _insecureTlsClient = IOClient(insecure);
    }
  }

  static const Duration _minRequestInterval = Duration(milliseconds: 800);
  static const Duration _apiHealthCacheTtl = Duration(minutes: 3);
  static const Set<String> _tlsFallbackHosts = <String>{
    'bangumi.tv', 'api.bgm.tv', 'bgmlist.com', 'lain.bgm.tv',
  };

  late http.Client _client;
  final bool _ownsClient;
  late http.Client _insecureTlsClient;
  final ValueNotifier<int> _activeRequests = ValueNotifier<int>(0);
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _requestQueue = Future<void>.value();
  int apiFastRetryBaseDelayMs = 120;
  String apiUserAgent = appUserAgent;
  final Map<String, DateTime> _subjectStartDates;
  Map<String, DateTime> get subjectStartDates =>
      Map<String, DateTime>.unmodifiable(_subjectStartDates);
  bool allowInsecureTlsFallback = true;
  bool? _apiAvailableCache;
  DateTime? _apiAvailableCheckedAt;
  void Function(String message)? onNetworkLog;

  // Cache for isSubjectStillAiring results with 30-min TTL.
  final Map<String, _AiringCacheEntry> _airingCache = <String, _AiringCacheEntry>{};
  static const Duration _airingCacheTtl = Duration(minutes: 30);

  bool _proxyEnabled;
  String _proxyHost;
  int _proxyPort;
  List<String> _proxyBypassList;

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

  static HttpClient _createHttpClient({bool allowBadCertificate = false}) {
    final HttpClient client = HttpClient();
    if (allowBadCertificate) {
      client.badCertificateCallback = (
        X509Certificate cert, String host, int port,
      ) => true;
    }
    return client;
  }

  bool _shouldBypassProxy(String host) {
    for (final String entry in _proxyBypassList) {
      if (entry.startsWith('*')) {
        if (host.endsWith(entry.substring(1))) return true;
      } else {
        if (host == entry) return true;
      }
    }
    return false;
  }

  void _applyProxy(HttpClient client) {
    if (!_proxyEnabled) return;
    final String proxyAddress = 'PROXY $_proxyHost:$_proxyPort';
    client.findProxy = (Uri uri) {
      if (_shouldBypassProxy(uri.host)) return 'DIRECT';
      return proxyAddress;
    };
  }

  void updateProxySettings(
    bool enabled, String host, int port, String bypass,
  ) {
    _proxyEnabled = enabled;
    _proxyHost = host;
    _proxyPort = port;
    _proxyBypassList = bypass
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();

    final HttpClient newClient = _createHttpClient();
    _applyProxy(newClient);
    if (_ownsClient) _client.close();
    _client = IOClient(newClient);

    final HttpClient newInsecureClient = _createHttpClient(allowBadCertificate: true);
    _applyProxy(newInsecureClient);
    _insecureTlsClient.close();
    _insecureTlsClient = IOClient(newInsecureClient);

    _logNetwork('代理配置已更新: ${_proxyEnabled ? "$_proxyHost:$_proxyPort" : "直连"}');
  }

  bool _isTlsCertificateFailure(Object error) {
    final String message = error.toString().toUpperCase();
    return message.contains('HANDSHAKEEXCEPTION') ||
        message.contains('CERTIFICATE_VERIFY_FAILED');
  }

  bool _shouldTryInsecureTlsFallback(Uri uri, Object error) {
    if (!allowInsecureTlsFallback || uri.scheme.toLowerCase() != 'https') return false;
    if (!_tlsFallbackHosts.contains(uri.host.toLowerCase())) return false;
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
      if (!_shouldTryInsecureTlsFallback(uri, e)) rethrow;

      _logNetwork(
        'TLS 证书校验失败[$purpose] ${_describeUrl(uri.toString())}，'
        '对该域名启用兼容重试（不安全 TLS）',
      );
      return _insecureTlsClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    }
  }

  Future<http.Response> _postWithTlsFallback(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    required String purpose,
  }) async {
    try {
      return await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      if (!_shouldTryInsecureTlsFallback(uri, e)) rethrow;
      _logNetwork(
        'TLS 证书校验失败[$purpose] ${_describeUrl(uri.toString())}，'
        '对该域名启用兼容重试（不安全 TLS）',
      );
      return _insecureTlsClient
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
    _insecureTlsClient.close();
    _activeRequests.dispose();
  }

  Future<T> _runTrackedRequest<T>(Future<T> Function() operation) async {
    _activeRequests.value += 1;
    try {
      return await operation();
    } finally {
      if (_activeRequests.value > 0) _activeRequests.value -= 1;
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
    if (value.isEmpty) return '';

    final String unescaped = value.replaceAll('&amp;', '&');

    if (unescaped.startsWith('//lain.bgm.tv/')) return 'https:$unescaped';
    if (unescaped.startsWith('http://lain.bgm.tv/')) return unescaped.replaceFirst('http://', 'https://');
    if (unescaped.startsWith('https://lain.bgm.tv/')) return unescaped;

    if (unescaped.contains('/pic/cover/')) {
      final String pathOnly = unescaped
          .replaceFirst(RegExp(r'^https?://[^/]+'), '')
          .replaceFirst(RegExp(r'^//[^/]+'), '');
      return 'https://lain.bgm.tv$pathOnly';
    }

    if (unescaped.startsWith('/r/') || unescaped.startsWith('/pic/')) return 'https://lain.bgm.tv$unescaped';
    if (unescaped.startsWith('//')) return 'https:$unescaped';
    if (unescaped.startsWith('http://')) return unescaped.replaceFirst('http://', 'https://');
    if (unescaped.startsWith('https://')) return unescaped;
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return 'https://bangumi.tv$value';
    return value;
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
        if (respectRateLimit) await _waitForRequestSlot();
        final Uri requestUri = Uri.parse(url);
        final http.Response response = await _runTrackedRequest(
          () => _getWithTlsFallback(requestUri, headers: headers, purpose: purpose),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _logNetwork('抓取成功[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes)');
          return utf8.decode(response.bodyBytes);
        }
        if (response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          _logNetwork('抓取重试[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode})');
          throw Exception('HTTP ${response.statusCode}');
        }
        _logNetwork('抓取失败[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode})');
        throw Exception('请求失败，状态码: ${response.statusCode}');
      } catch (e) {
        lastError = e;
        _logNetwork('抓取异常[$purpose] ${_describeUrl(url)} ($e)');
        await Future<void>.delayed(Duration(milliseconds: retryBaseDelayMs * (i + 1)));
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
        if (respectRateLimit) await _waitForRequestSlot();
        final Uri requestUri = Uri.parse(url);
        final http.Response response = await _runTrackedRequest(
          () => _getWithTlsFallback(requestUri, headers: imageRequestHeaders, purpose: purpose),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _logNetwork('抓取成功[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes)');
          return response;
        }
        if (response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          _logNetwork('抓取重试[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode})');
          throw Exception('HTTP ${response.statusCode}');
        }
        _logNetwork('抓取失败[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode})');
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

  Future<String> _postWithRetry(
    String url, {
    required String purpose,
    Map<String, String> headers = requestHeaders,
    Map<String, dynamic>? body,
    bool respectRateLimit = true,
    int retryBaseDelayMs = 800,
  }) async {
    Object? lastError;
    _logNetwork('开始 POST[$purpose] ${_describeUrl(url)}');
    if (url.startsWith(bangumiApiBaseUrl)) {
      _logNetwork('当前 API UA: $effectiveApiUserAgent');
    }
    for (int i = 0; i < 3; i++) {
      try {
        _logNetwork('尝试 ${i + 1}/3 POST[$purpose] ${_describeUrl(url)}');
        if (respectRateLimit) await _waitForRequestSlot();
        final Uri requestUri = Uri.parse(url);
        final String jsonBody = body != null ? jsonEncode(body) : '';
        final http.Response response = await _runTrackedRequest(
          () => _postWithTlsFallback(requestUri, headers: headers, body: jsonBody, purpose: purpose),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _logNetwork('POST 成功[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes)');
          return utf8.decode(response.bodyBytes);
        }
        if (response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          _logNetwork('POST 重试[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode})');
          throw Exception('HTTP ${response.statusCode}');
        }
        _logNetwork('POST 失败[$purpose] ${_describeUrl(url)} (HTTP ${response.statusCode})');
        throw Exception('请求失败，状态码: ${response.statusCode}');
      } catch (e) {
        lastError = e;
        _logNetwork('POST 异常[$purpose] ${_describeUrl(url)} ($e)');
        await Future<void>.delayed(Duration(milliseconds: retryBaseDelayMs * (i + 1)));
      }
    }
    _logNetwork('POST 终止[$purpose] ${_describeUrl(url)} (${lastError ?? '未知错误'})');
    throw Exception(lastError?.toString() ?? '请求失败');
  }

  static String _buildArchiveUrl(DateTime now) {
    final int q = ((now.month - 1) ~/ 3) + 1;
    return '$bgmlistArchiveBaseUrl/${now.year}q$q';
  }

  Future<List<DaySchedule>> fetchCalendarSchedule() async {
    _subjectStartDates.clear();
    _airingCache.removeWhere(
      (_, _AiringCacheEntry e) =>
          DateTime.now().difference(e.cachedAt) > _airingCacheTtl * 2,
    );
    final String url = _buildArchiveUrl(DateTime.now());
    final String pageText = await _getWithRetry(url, purpose: '抓取 BGMLIST 当季番组页面');
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

  Future<bool> isSubjectStillAiring(String subjectId) async {
    if (subjectId.isEmpty) return false;

    // Check cache first.
    final _AiringCacheEntry? cached = _airingCache[subjectId];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _airingCacheTtl) {
      return cached.result;
    }

    final bool result = await _checkSubjectStillAiring(subjectId);
    _airingCache[subjectId] = _AiringCacheEntry(result, DateTime.now());
    return result;
  }

  Future<bool> _checkSubjectStillAiring(String subjectId) async {
    if (subjectId.isEmpty) return false;
    // Throttle OnAir checks — same slot covers both API calls below.
    await _waitForRequestSlot();
    final Map<String, dynamic>? subject = await _fetchSubjectFromApi(subjectId);
    if (subject == null || subject.isEmpty) return false;
    final int? totalEps = _readInt(subject['total_episodes']) ?? _readInt(subject['eps']);
    if (totalEps == null || totalEps <= 0) return false;

    final List<Map<String, dynamic>> episodes = await _fetchMainEpisodesFromApi(subjectId);
    if (episodes.isEmpty) return false;

    final DateTime todayStartJst = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 9));
    final DateTime jstDayStart =
        DateTime.utc(todayStartJst.year, todayStartJst.month, todayStartJst.day);

    int aired = 0;
    for (final Map<String, dynamic> ep in episodes) {
      final int epNo = (_readDouble(ep['ep']) ?? _readDouble(ep['sort']) ?? 0).round();
      if (epNo <= 0) continue;
      final String airdateText = _readString(ep['airdate']);
      if (airdateText.isEmpty) continue;
      final DateTime? airdate = _readDate(airdateText);
      if (airdate != null && !airdate.isAfter(jstDayStart)) aired += 1;
    }
    return aired < totalEps;
  }

  DateTime? _toJstDateTimeFromIso(String isoText) {
    if (isoText.isEmpty) return null;
    try {
      return DateTime.parse(isoText).toUtc().add(const Duration(hours: 9));
    } catch (_) {
      return null;
    }
  }

  String _toJstTimeFromIso(String isoText) {
    final DateTime? jst = _toJstDateTimeFromIso(isoText);
    if (jst == null) return '';
    return '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}';
  }

  String _extractJstTimeFromBgmListItem(Map<String, dynamic> item) {
    final String broadcast = (item['broadcast'] as String? ?? '').trim();
    if (broadcast.isNotEmpty) {
      final RegExpMatch? match = RegExp(r'^R/([^/]+)/').firstMatch(broadcast);
      final String fromBroadcast = _toJstTimeFromIso((match?.group(1) ?? '').trim());
      if (fromBroadcast.isNotEmpty) return fromBroadcast;
    }
    return _toJstTimeFromIso(_readString(item['begin']));
  }

  Iterable<String> _extractJpTitlesFromBgmListItem(Map<String, dynamic> item) {
    final Set<String> titles = <String>{};
    final String mainTitle = (item['title'] as String? ?? '').trim();
    if (mainTitle.isNotEmpty) titles.add(mainTitle);

    final dynamic titleTranslate = item['titleTranslate'];
    if (titleTranslate is Map) {
      final dynamic ja = titleTranslate['ja'];
      if (ja is List) {
        for (final dynamic raw in ja) {
          final String value = raw?.toString().trim() ?? '';
          if (value.isNotEmpty) titles.add(value);
        }
      }
    }
    return titles.toList(growable: false);
  }

  List<BgmListOnAirEntry> parseBgmListOnAirEntries(String jsonText) {
    if (jsonText.trim().isEmpty) return <BgmListOnAirEntry>[];
    try {
      final dynamic decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return <BgmListOnAirEntry>[];
      final dynamic itemsRaw = decoded['items'];
      if (itemsRaw is! List) return <BgmListOnAirEntry>[];

      return itemsRaw.whereType<Map<String, dynamic>>().map((raw) {
        final String timeText = _extractJstTimeFromBgmListItem(raw);
        if (timeText.isEmpty) return null;
        final List<String> jpTitles = _extractJpTitlesFromBgmListItem(raw)
            .where((t) => t.trim().isNotEmpty).toList();
        if (jpTitles.isEmpty) return null;
        return BgmListOnAirEntry(timeJst: timeText, jpTitles: jpTitles);
      }).whereType<BgmListOnAirEntry>().toList();
    } catch (_) {
      return <BgmListOnAirEntry>[];
    }
  }

  String extractBangumiIdFromBgmListItem(Map<String, dynamic> item) {
    final dynamic sitesRaw = item['sites'];
    if (sitesRaw is! List) return '';
    for (final dynamic siteRaw in sitesRaw) {
      if (siteRaw is! Map<String, dynamic>) continue;
      final String site = _readString(siteRaw['site']).toLowerCase();
      if (site == 'bangumi' || site == 'bangumi.tv') {
        final String id = _readString(siteRaw['id']);
        if (RegExp(r'^\d+$').hasMatch(id)) return id;
      }
    }
    return '';
  }

  String _extractCnTitleFromBgmListItem(Map<String, dynamic> item) {
    final dynamic titleTranslate = item['titleTranslate'];
    if (titleTranslate is! Map) return '';
    for (final String key in <String>['zh-Hans', 'zh-Hant', 'zh']) {
      final dynamic raw = titleTranslate[key];
      if (raw is List) {
        for (final dynamic one in raw) {
          final String text = one?.toString().trim() ?? '';
          if (text.isNotEmpty) return text;
        }
      }
    }
    return '';
  }

  String _extractCoverUrlFromBgmListItem(Map<String, dynamic> item) {
    final dynamic imagesRaw = item['images'];
    if (imagesRaw is! Map<String, dynamic>) return '';
    for (final String key in <String>['common', 'large', 'medium', 'small', 'grid']) {
      final String url = _normalizeImageUrl(_readString(imagesRaw[key]));
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  DateTime? _extractBroadcastStartJstFromBgmListItem(Map<String, dynamic> item) {
    final String broadcast = _readString(item['broadcast']);
    if (broadcast.isEmpty) return null;
    final RegExpMatch? match = RegExp(r'^R/([^/]+)/').firstMatch(broadcast);
    return _toJstDateTimeFromIso((match?.group(1) ?? '').trim());
  }

  DateTime? _extractBeginJstFromBgmListItem(Map<String, dynamic> item) {
    final String begin = _readString(item['begin']);
    if (begin.isNotEmpty) {
      final DateTime? beginJst = _toJstDateTimeFromIso(begin);
      if (beginJst != null) return beginJst;
    }
    return _extractBroadcastStartJstFromBgmListItem(item);
  }

  int? _extractBroadcastPeriodDaysFromBgmListItem(Map<String, dynamic> item) {
    final String broadcast = _readString(item['broadcast']);
    if (broadcast.isEmpty) return null;
    final RegExpMatch? match = RegExp(r'^R/[^/]+/P(\d+)([DWM])$').firstMatch(broadcast);
    if (match == null) return null;
    final int? amount = int.tryParse(match.group(1) ?? '');
    final String unit = match.group(2) ?? '';
    if (amount == null || amount <= 0) return null;
    if (unit == 'D') return amount;
    if (unit == 'W') return amount * 7;
    return null;
  }

  List<BgmListScheduleCandidate> parseBgmListScheduleCandidates(String jsonText) {
    if (jsonText.trim().isEmpty) return <BgmListScheduleCandidate>[];
    try {
      final dynamic decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return <BgmListScheduleCandidate>[];
      final dynamic itemsRaw = decoded['items'];
      if (itemsRaw is! List) return <BgmListScheduleCandidate>[];

      return itemsRaw.whereType<Map<String, dynamic>>().map((raw) {
        final String subjectId = extractBangumiIdFromBgmListItem(raw);
        if (subjectId.isEmpty) return null;

        final String titleJp = _readString(raw['title']);
        if (titleJp.isEmpty) return null;

        final DateTime? beginJst = _extractBeginJstFromBgmListItem(raw);
        if (beginJst == null) return null;

        final DateTime? broadcastStartJst = _extractBroadcastStartJstFromBgmListItem(raw);
        final DateTime weekdaySource = broadcastStartJst ?? beginJst;
        final String weekdayJst = weekdayMap[weekdaySource.weekday] ?? '';
        if (weekdayJst.isEmpty) return null;

        final String updateTimeJst = _extractJstTimeFromBgmListItem(raw);
        if (updateTimeJst.isEmpty) return null;

        final int? periodDays = _extractBroadcastPeriodDaysFromBgmListItem(raw);
        if (periodDays == null || periodDays <= 0) return null;

        return BgmListScheduleCandidate(
          subjectId: subjectId,
          subjectUrl: 'https://bangumi.tv/subject/$subjectId',
          titleJp: titleJp,
          titleCn: _extractCnTitleFromBgmListItem(raw),
          coverUrl: _extractCoverUrlFromBgmListItem(raw),
          weekdayJst: weekdayJst,
          updateTimeJst: updateTimeJst,
          beginJst: beginJst,
          periodDays: periodDays,
        );
      }).whereType<BgmListScheduleCandidate>().toList();
    } catch (_) {
      return <BgmListScheduleCandidate>[];
    }
  }

  String _extractSubjectId(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
    final RegExp pathPattern = RegExp(r'/subject/(\d+)');
    final RegExpMatch? pathMatch = pathPattern.firstMatch(trimmed);
    if (pathMatch != null) return pathMatch.group(1) ?? '';
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final RegExpMatch? uriMatch = pathPattern.firstMatch(uri.path);
      if (uriMatch != null) return uriMatch.group(1) ?? '';
    }
    return '';
  }

  String _readString(dynamic value) {
    if (value == null) return '';
    final String text = value.toString().trim();
    return text == 'null' ? '' : text;
  }

  int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  DateTime? _readDate(String rawDate) {
    final String value = rawDate.trim();
    if (value.isEmpty) return null;
    try { return DateTime.parse(value); } catch (_) { return null; }
  }

  String _pickBestImageUrlFromSubjectApi(Map<String, dynamic> subjectJson) {
    final dynamic imagesRaw = subjectJson['images'];
    if (imagesRaw is! Map<String, dynamic>) return '';
    for (final String key in <String>['common', 'large', 'medium', 'small', 'grid']) {
      final String url = _normalizeImageUrl(_readString(imagesRaw[key]));
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  Future<Map<String, dynamic>?> _fetchSubjectFromApi(String subjectId) async {
    if (subjectId.isEmpty) return null;
    final String body = await _getWithRetry(
      '$bangumiApiBaseUrl/v0/subjects/$subjectId',
      purpose: '抓取 Bangumi API 条目信息',
      headers: _apiRequestHeaders,
      respectRateLimit: false,
      retryBaseDelayMs: apiFastRetryBaseDelayMs,
    );
    final dynamic decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  /// Public wrapper for fetching full Subject JSON from the Bangumi API.
  Future<Map<String, dynamic>?> fetchSubjectFromApi(String subjectId) async {
    return _fetchSubjectFromApi(subjectId);
  }

  Future<int?> fetchSubjectTotalEpisodes(String subjectId) async {
    final Map<String, dynamic>? subject = await _fetchSubjectFromApi(subjectId);
    if (subject == null || subject.isEmpty) return null;
    final int? total = _readInt(subject['total_episodes']) ?? _readInt(subject['eps']);
    if (total == null || total <= 0) return null;
    return total;
  }

  Future<List<Map<String, dynamic>>> _fetchMainEpisodesFromApi(String subjectId) async {
    if (subjectId.isEmpty) return <Map<String, dynamic>>[];
    final String body = await _getWithRetry(
      '$bangumiApiBaseUrl/v0/episodes?subject_id=$subjectId&type=0&limit=200&offset=0',
      purpose: '抓取 Bangumi API 分集列表',
      headers: _apiRequestHeaders,
      respectRateLimit: false,
      retryBaseDelayMs: apiFastRetryBaseDelayMs,
    );
    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return <Map<String, dynamic>>[];
    final dynamic data = decoded['data'];
    if (data is! List) return <Map<String, dynamic>>[];
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<SubjectProgress?> _tryFetchSubjectProgressViaApi(
    String targetUrl, {
    String scheduleTime = '',
    String scheduleWeekday = '',
    int displayTimezoneOffsetMinutes = BroadcastTimeConverter.jstOffsetMinutes,
  }) async {
    final String subjectId = _extractSubjectId(targetUrl);
    if (subjectId.isEmpty) return null;

    Map<String, dynamic>? subject;
    List<Map<String, dynamic>> episodes = <Map<String, dynamic>>[];

    await Future.wait(<Future<void>>[
      (() async { subject = await _fetchSubjectFromApi(subjectId); })(),
      (() async { episodes = await _fetchMainEpisodesFromApi(subjectId); })(),
    ]);

    if (subject == null || subject!.isEmpty) return null;
    if (episodes.isEmpty) return null;
    final Map<String, dynamic> subjectData = subject!;

    final List<Map<String, dynamic>> sorted = List<Map<String, dynamic>>.from(episodes)
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final double aNo = _readDouble(a['ep']) ?? _readDouble(a['sort']) ?? 0;
        final double bNo = _readDouble(b['ep']) ?? _readDouble(b['sort']) ?? 0;
        return aNo.compareTo(bNo);
      });

    final int normalizedDisplayOffset =
        BroadcastTimeConverter.normalizeTimezoneOffsetMinutes(displayTimezoneOffsetMinutes);
    final DateTime nowInDisplay =
        DateTime.now().toUtc().add(Duration(minutes: normalizedDisplayOffset));
    final DateTime todayStartInDisplay = DateTime.utc(
      nowInDisplay.year, nowInDisplay.month, nowInDisplay.day,
    );

    int airedCount = 0;
    int? latestAiredEp;
    String? latestAiredDisplayTitle;
    DateTime? latestAiredAtInDisplay;
    int? nextEp;
    final List<int> episodeCommentCounts = <int>[];
    final Map<int, String> episodeTitleByEp = <int, String>{};

    for (final Map<String, dynamic> ep in sorted) {
      final int epNo = (_readDouble(ep['ep']) ?? _readDouble(ep['sort']) ?? 0).round();
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
          isAired = !DateTime.utc(airdate.year, airdate.month, airdate.day).isAfter(todayStartInDisplay);
        }
      } else {
        isAired = !DateTime.utc(airdate.year, airdate.month, airdate.day).isAfter(todayStartInDisplay);
      }

      final String cn = _readString(ep['name_cn']);
      final String origin = _readString(ep['name']);
      final String display = cn.isNotEmpty ? cn : origin;
      if (epNo > 0 && display.isNotEmpty) episodeTitleByEp[epNo] = display;

      if (isAired) {
        airedCount += 1;
        if (epNo > 0) {
          latestAiredEp = epNo;
          latestAiredAtInDisplay = airedAtInDisplay ??
              (airdate != null
                  ? DateTime.utc(airdate.year, airdate.month, airdate.day)
                  : null);
        }
        if (display.isNotEmpty) latestAiredDisplayTitle = display;
      } else if (nextEp == null && epNo > 0) {
        nextEp = epNo;
      }
    }

    final int totalEpsListed = sorted.length;
    final Map<String, dynamic>? ratingData = subjectData['rating'] as Map<String, dynamic>?;
    final double? ratingScore = _readDouble(ratingData?['score']);
    final int? totalEpsDeclared = _readInt(subjectData['total_episodes']) ?? _readInt(subjectData['eps']);
    final int? totalEps = totalEpsDeclared ?? (totalEpsListed > 0 ? totalEpsListed : null);

    String? latestAiredAtLabel;
    if (latestAiredAtInDisplay != null) {
      final String wd = weekdayMap[latestAiredAtInDisplay.weekday] ?? '';
      final String hh = latestAiredAtInDisplay.hour.toString().padLeft(2, '0');
      final String mm = latestAiredAtInDisplay.minute.toString().padLeft(2, '0');
      latestAiredAtLabel = '$wd $hh:$mm ${BroadcastTimeConverter.formatUtcOffsetLabel(normalizedDisplayOffset)}';
    }

    return SubjectProgress(
      totalEpsDeclared: totalEpsDeclared,
      totalEpsListed: totalEpsListed,
      airedEps: airedCount,
      latestAiredEp: latestAiredEp,
      latestAiredCnTitle: latestAiredDisplayTitle,
      latestAiredAtLabel: latestAiredAtLabel,
      latestAiredAt: latestAiredAtInDisplay,
      nextEp: nextEp,
      ratingScore: ratingScore,
      episodeCommentCounts: List<int>.unmodifiable(episodeCommentCounts),
      episodeTitleByEp: Map<int, String>.unmodifiable(episodeTitleByEp),
      progressText: totalEps == null ? '未知' : '$airedCount/$totalEps',
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
    if (apiProgress != null) return apiProgress;
    throw Exception('Bangumi API 未返回有效进度数据');
  }

  Future<String> fetchSubjectCoverUrl(String subjectUrl) async {
    if (subjectUrl.isEmpty) return '';
    final String subjectId = _extractSubjectId(subjectUrl);
    if (subjectId.isEmpty) return '';
    final Map<String, dynamic>? subject = await _fetchSubjectFromApi(subjectId);
    if (subject == null) return '';
    return _pickBestImageUrlFromSubjectApi(subject);
  }

  static String _standardizeWeekday(String chineseDay) {
    switch (chineseDay) {
      case '日': return '星期日';
      case '一': return '星期一';
      case '二': return '星期二';
      case '三': return '星期三';
      case '四': return '星期四';
      case '五': return '星期五';
      case '六': return '星期六';
      default: return '';
    }
  }

  List<DaySchedule> parseDailySchedule(String pageText) {
    final dom.Document document = html_parser.parse(pageText);
    final Map<String, List<SubjectItem>> dayGroups = <String, List<SubjectItem>>{
      for (final String d in orderedWeekdays) d: <SubjectItem>[],
    };

    for (final dom.Element article in document.querySelectorAll('article')) {
      final dom.Element? h3 = article.querySelector('h3');
      final String cnName = h3?.text.trim() ?? '';
      if (cnName.isEmpty) continue;

      final String originName =
          article.querySelector('[class^="BangumiItem_subTitle"]')?.text.trim() ?? '';

      final String fullText = article.text;
      final RegExpMatch? timeMatch = RegExp(
        r'每周([日月一二三四五六七八九十]+)\s*(\d{2}:\d{2})',
      ).firstMatch(fullText);
      if (timeMatch == null) continue;
      final String weekday = _standardizeWeekday(timeMatch.group(1)!);
      final String updateTime = timeMatch.group(2)!;
      if (weekday.isEmpty) continue;

      final dom.Element? bgmLink = article.querySelector('a[href*="bangumi.tv/subject/"]');
      if (bgmLink == null) continue;
      final String href = bgmLink.attributes['href'] ?? '';
      final RegExpMatch? idMatch = RegExp(r'/subject/(\d+)').firstMatch(href);
      final String subjectId = idMatch?.group(1) ?? '';
      if (subjectId.isEmpty) continue;

      final RegExpMatch? startMatch = RegExp(r'(\d{4}-\d{2}-\d{2})\s*起').firstMatch(fullText);
      if (startMatch != null) {
        final DateTime? parsed = DateTime.tryParse(startMatch.group(1)!);
        if (parsed != null) _subjectStartDates[subjectId] = parsed;
      }

      dayGroups[weekday]!.add(SubjectItem(
        subjectId: subjectId,
        subjectUrl: href,
        nameCn: cnName,
        nameOrigin: originName,
        coverUrl: '',
        updateTime: updateTime,
      ));
    }

    return orderedWeekdays
        .where((wd) => (dayGroups[wd]?.isNotEmpty ?? false))
        .map((wd) {
          dayGroups[wd]!.sort((a, b) => a.updateTime.compareTo(b.updateTime));
          return DaySchedule(weekday: wd, items: dayGroups[wd]!);
        })
        .toList();
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
        if (match != null) totalEpsDeclared = int.tryParse(match.group(1)!);
      } else if (text.startsWith('放送开始:') || text.startsWith('放送开始：')) {
        final List<String> parts = text.split(RegExp(r'[:：]'));
        if (parts.length > 1) airStart = parts.sublist(1).join(':').trim();
      } else if (text.startsWith('放送星期:') || text.startsWith('放送星期：')) {
        final List<String> parts = text.split(RegExp(r'[:：]'));
        if (parts.length > 1) airWeekday = parts.sublist(1).join(':').trim();
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

    for (final dom.Element discussLink in document.querySelectorAll('a[href^="/subject/ep/"]')) {
      final String href = discussLink.attributes['href']?.trim() ?? '';
      final RegExpMatch? epMatch = RegExp(r'^/subject/ep/(\d+)').firstMatch(href);
      if (epMatch == null) continue;
      final String epId = epMatch.group(1) ?? '';
      if (epId.isEmpty) continue;

      final dom.Element? countNode =
          discussLink.parent?.querySelector('small.na') ??
          discussLink.parent?.parent?.querySelector('small.na') ??
          discussLink.nextElementSibling;
      final String countText = countNode?.text.trim() ?? '';
      final RegExpMatch? countMatch = RegExp(r'\+?(\d+)').firstMatch(countText);
      final int? count = countMatch != null ? int.tryParse(countMatch.group(1) ?? '') : null;
      if (count == null) continue;
      result[epId] = count;
    }

    return result;
  }

  Map<String, String> parseSubjectCnTitleByEpId(String subjectPageText) {
    final dom.Document document = html_parser.parse(subjectPageText);
    final Map<String, String> result = <String, String>{};

    for (final dom.Element popup in document.querySelectorAll('div.prg_popup[id^="prginfo_"]')) {
      final String idAttr = popup.id.trim();
      final RegExpMatch? idMatch = RegExp(r'^prginfo_(\d+)$').firstMatch(idAttr);
      if (idMatch == null) continue;
      final String epId = idMatch.group(1) ?? '';
      if (epId.isEmpty) continue;

      final dom.Element? tipNode = popup.querySelector('span.tip');
      if (tipNode == null) continue;

      final String html = tipNode.innerHtml;
      final RegExpMatch? cnMatch = RegExp(
        r'中文标题\s*[:：]\s*([^<\r\n]+)',
        caseSensitive: false,
      ).firstMatch(html);
      if (cnMatch == null) continue;
      final String title = (cnMatch.group(1) ?? '').trim();
      if (title.isNotEmpty && !result.containsKey(epId)) result[epId] = title;
    }

    return result;
  }

  EpisodeProgress parseEpisodeProgress(
    String epPageText, {
    Map<String, int>? discussionByEpId,
  }) {
    final dom.Document document = html_parser.parse(epPageText);
    final List<dom.Element> rows = document.querySelectorAll('li.line_odd, li.line_even');

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
      if (link == null) continue;

      final String linkText = link.text.trim();
      final RegExpMatch? match = RegExp(r'^(\d+)\.').firstMatch(linkText);
      if (match == null) continue;

      final RegExpMatch? titleMatch = RegExp(r'^\d+\.\s*(.+)$').firstMatch(linkText);
      final String originTitle = (titleMatch?.group(1) ?? '').trim();

      final int? epNo = int.tryParse(match.group(1)!);
      if (epNo == null) continue;

      final String epHref = link.attributes['href']?.trim() ?? '';
      final RegExpMatch? epIdMatch = RegExp(r'^/ep/(\d+)').firstMatch(epHref);
      final String epId = epIdMatch?.group(1) ?? '';

      totalNumericEps += 1;
      numericEpisodesInOrder.add(epNo);
      episodeIdsInOrder.add(epId);
      episodeOriginTitlesInOrder.add(originTitle);

      final dom.Element? statusNode = row.querySelector('span.epAirStatus span');
      final String classes = statusNode?.className ?? '';
      final bool isAired = classes.split(' ').contains('Air');

      if (isAired) {
        airedNumericEps += 1;
        if (latestAiredEp == null || epNo > latestAiredEp) {
          latestAiredEp = epNo;
          latestAiredEpId = epId.isEmpty ? latestAiredEpId : epId;
          latestAiredOriginTitle = originTitle.isEmpty ? latestAiredOriginTitle : originTitle;
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

  /// Search Bangumi subjects by keyword. Returns up to 10 anime entries.
  ///
  /// [airDateYearFrom] / [airDateYearTo] — filter by air date year range,
  ///   e.g. from=2020, to=2025 → 2020‑01‑01 ≤ airdate < 2026‑01‑01.
  /// [minRating] — minimum rating threshold, e.g. 7 → rating ≥ 7.
  /// [minRatingCount] — minimum rating count, e.g. 1000 → rating_count ≥ 1000.
  /// [tags] — public meta_tags filter (AND logic, prefix `-` to exclude).
  Future<SearchSubjectsResponse> searchSubjects(
    String keyword, {
    int limit = 10,
    int offset = 0,
    String? sort,
    int? airDateYearFrom,
    int? airDateYearTo,
    double? minRating,
    int? minRatingCount,
    List<String>? tags,
  }) async {
    if (keyword.trim().isEmpty) {
      return SearchSubjectsResponse(total: 0, results: <SearchSubjectResult>[]);
    }

    final Map<String, String> headers = Map<String, String>.from(
      _apiRequestHeaders,
    )..['Content-Type'] = 'application/json';

    final Map<String, dynamic> filter = <String, dynamic>{
      'type': <int>[2],
    };
    if (airDateYearFrom != null || airDateYearTo != null) {
      final List<String> airDate = <String>[];
      if (airDateYearFrom != null) {
        airDate.add('>=${airDateYearFrom}-01-01');
      }
      if (airDateYearTo != null) {
        airDate.add('<${airDateYearTo + 1}-01-01');
      }
      filter['air_date'] = airDate;
    }
    if (minRating != null) {
      filter['rating'] = <String>['>=${minRating.toStringAsFixed(0)}'];
    }
    if (minRatingCount != null) {
      filter['rating_count'] = <String>['>=$minRatingCount'];
    }
    if (tags != null && tags.isNotEmpty) {
      filter['meta_tags'] = tags;
    }

    final String body = await _postWithRetry(
      '$bangumiApiBaseUrl/v0/search/subjects?limit=${limit.clamp(1, 20)}&offset=$offset',
      purpose: '搜索番剧条目',
      headers: headers,
      body: <String, dynamic>{
        'keyword': keyword,
        'sort': sort ?? 'heat',
        'filter': filter,
      },
    );

    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return SearchSubjectsResponse(total: 0, results: <SearchSubjectResult>[]);
    }

    final int total = (decoded['total'] as num?)?.toInt() ?? 0;
    final dynamic dataRaw = decoded['data'];
    if (dataRaw is! List) {
      return SearchSubjectsResponse(total: total, results: <SearchSubjectResult>[]);
    }

    final List<SearchSubjectResult> results = <SearchSubjectResult>[];
    for (final dynamic raw in dataRaw) {
      if (raw is! Map<String, dynamic>) continue;

      final int id = (raw['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;

      final String name = _readString(raw['name']);
      final String nameCn = _readString(raw['name_cn']);

      // Extract cover URL from images object or image field
      String coverUrl = '';
      final dynamic images = raw['images'];
      if (images is Map<String, dynamic>) {
        for (final String key in <String>['common', 'large', 'medium', 'small', 'grid']) {
          coverUrl = _normalizeImageUrl(_readString(images[key]));
          if (coverUrl.isNotEmpty) break;
        }
      }
      if (coverUrl.isEmpty) coverUrl = _normalizeImageUrl(_readString(raw['image']));

      if (results.length < 5) {
        _logNetwork('搜索结果: id=$id name=$name cover=${coverUrl.length > 60 ? "${coverUrl.substring(0, 60)}..." : coverUrl}');
      }

      final double? ratingScore = (raw['rating'] is Map<String, dynamic>)
          ? _readDouble((raw['rating'] as Map<String, dynamic>)['score'])
          : null;
      final String airDate = _readString(raw['date']);
      final int popularity = (raw['rating'] is Map<String, dynamic>)
          ? _readInt((raw['rating'] as Map<String, dynamic>)['total']) ?? 0
          : 0;

      if (results.length < 5) {
        _logNetwork('搜索条目: id=$id name=$name popularity=$popularity ratingScore=$ratingScore');
      }

      results.add(SearchSubjectResult(
        subject: SubjectItem(
          subjectId: id.toString(),
          subjectUrl: 'https://bangumi.tv/subject/$id',
          nameCn: nameCn,
          nameOrigin: name,
          coverUrl: coverUrl,
          updateTime: airDate,
        ),
        ratingScore: ratingScore,
        airDate: airDate,
        popularity: popularity,
      ));
    }
    return SearchSubjectsResponse(total: total, results: results);
  }
}

/// Result of a Bangumi subject search, pairing the SubjectItem with
/// search-specific display data.
class SearchSubjectResult {
  const SearchSubjectResult({
    required this.subject,
    this.ratingScore,
    this.airDate = '',
    this.popularity = 0,
  });

  final SubjectItem subject;
  final double? ratingScore;
  final String airDate;
  final int popularity;
}

/// Response wrapper for search results, including total count for pagination.
class SearchSubjectsResponse {
  const SearchSubjectsResponse({
    required this.total,
    required this.results,
  });

  final int total;
  final List<SearchSubjectResult> results;
}