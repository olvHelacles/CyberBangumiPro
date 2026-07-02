import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Manages a local mihomo (clash-meta) proxy process for bypassing network
/// restrictions, so Bangumi API requests are routed through the proxy.
class ClashManager {
  ClashManager._();

  static const String _binaryName = 'mihomo.exe';
  static const String _configName = 'clash_config.yaml';
  static const int _healthCheckIntervalMs = 800;
  static const int _maxHealthCheckAttempts = 15;
  static const int _shutdownTimeoutSeconds = 5;
  static const String _apiHost = '127.0.0.1';
  static const int _apiPort = 57737;
  static const String _apiSecret = 'cbgm-pro-clash';

  static final ClashManager _instance = ClashManager._();
  static ClashManager get instance => _instance;

  Process? _process;
  bool _started = false;
  String? _binaryPath;
  String? _configPath;
  String _currentNode = '';
  int _currentLatency = 0;

  bool get isRunning => _process != null;
  String get currentNode => _currentNode;
  int get currentLatency => _currentLatency;

  /// Query the Clash REST API for the current proxy node and its latency.
  Future<void> refreshNodeInfo() async {
    if (!isRunning) {
      _currentNode = '';
      _currentLatency = 0;
      return;
    }
    try {
      final HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);

      // Get the current node from the "Proxy" group.
      final Uri groupUri = Uri(
        scheme: 'http',
        host: _apiHost,
        port: _apiPort,
        path: '/proxies/Proxy',
      );
      final HttpClientRequest req = await client.getUrl(groupUri);
      req.headers.set('Authorization', 'Bearer $_apiSecret');
      final HttpClientResponse resp = await req.close();
      final String body = await resp.transform(utf8.decoder).join();
      client.close();

      if (resp.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(body)
            as Map<String, dynamic>;
        final String now = data['now'] as String? ?? '';
        if (now.isNotEmpty) {
          _currentNode = now;
          _currentLatency = 0;

          // Query the individual proxy for its latest delay.
          try {
            final Uri proxyUri = Uri(
              scheme: 'http',
              host: _apiHost,
              port: _apiPort,
              path: '/proxies/$now',
            );
            final HttpClientRequest req2 = await client.getUrl(proxyUri);
            req2.headers.set('Authorization', 'Bearer $_apiSecret');
            final HttpClientResponse resp2 = await req2.close();
            final String body2 = await resp2.transform(utf8.decoder).join();
            if (resp2.statusCode == 200) {
              final Map<String, dynamic> proxyData = jsonDecode(body2)
                  as Map<String, dynamic>;
              final List<dynamic> history = proxyData['history'] as List<dynamic>? ?? <dynamic>[];
              if (history.isNotEmpty) {
                final Map<String, dynamic> last = history.last as Map<String, dynamic>;
                _currentLatency = (last['delay'] as num?)?.toInt() ?? 0;
              }
            }
            client.close();
          } catch (_) {
            // Non-fatal; refresh will be retried.
          }
        }
      }
    } catch (_) {
      // Non-fatal; refresh will be retried on next dialog open.
    }
  }

  /// Ensure the clash binary is available and the proxy is ready.
  ///
  /// If [savedSubscriptionUrl] is non-empty the config will be generated from
  /// it (instead of the empty template) so the proxy has usable nodes from the
  /// start.
  Future<bool> start({String? savedSubscriptionUrl}) async {
    if (_started) {
      return true;
    }
    _started = true;

    try {
      await _extractBinary();
      if (savedSubscriptionUrl != null &&
          savedSubscriptionUrl.trim().isNotEmpty &&
          await _configNeedsUpdate(savedSubscriptionUrl.trim())) {
        await applySubscription(savedSubscriptionUrl.trim());
      } else {
        await _ensureConfig();
      }
      await _spawnProcess();
      await _waitUntilReady();
      return true;
    } catch (e) {
      _started = false;
      rethrow;
    }
  }

  /// Stop the clash process and clean up.
  Future<void> stop() async {
    if (_process == null) return;

    try {
      _process!.stdin.close();
      _process!.kill(ProcessSignal.sigterm);
      await _process!.exitCode.timeout(
        Duration(seconds: _shutdownTimeoutSeconds),
        onTimeout: () {
          _process!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (_) {
      try {
        _process?.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }

    _process = null;
    _started = false;
  }

  /// Release the process handle without waiting for a graceful shutdown.
  /// The OS will terminate the child when our process exits.
  void detach() {
    _process = null;
    _started = false;
  }

  /// Immediately terminate the clash process (no graceful wait).
  void kill() {
    if (_process == null) return;
    try {
      _process!.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _process = null;
    _started = false;
  }

  /// Replace the current clash configuration with the given subscription URL
  /// and restart the proxy.
  ///
  /// If [subscriptionUrl] is empty or null, no config change is made.
  Future<void> applySubscription(String? subscriptionUrl) async {
    if (subscriptionUrl == null || subscriptionUrl.trim().isEmpty) return;
    final String url = subscriptionUrl.trim();

    final String workDir = Directory.current.path;
    const String configName = 'clash_config.yaml';
    final String configPath =
        '$workDir${Platform.pathSeparator}$configName';

    final String newConfig = '''
# Clash configuration — CyberBangumi Pro
# Auto-generated from subscription URL.
port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: warning
external-controller: 127.0.0.1:57737
secret: "cbgm-pro-clash"

proxy-providers:
  sub:
    type: http
    url: "$url"
    interval: 86400
    path: ./sub_provider.yaml
    health-check:
      enable: true
      url: https://api.bgm.tv/v0/subjects/1
      interval: 300

proxy-groups:
  - name: "Proxy"
    type: url-test
    use:
      - sub
    url: https://api.bgm.tv/v0/subjects/1
    interval: 300
    tolerance: 50

rules:
  - MATCH,Proxy
''';

    await File(configPath).writeAsString(newConfig, flush: true);
    _configPath = configPath;
  }

  /// Returns true when the current config file does not already contain the
  /// given [subscriptionUrl], so a rewrite + restart is worthwhile.
  Future<bool> _configNeedsUpdate(String subscriptionUrl) async {
    final String workDir = Directory.current.path;
    final File config = File(
      '$workDir${Platform.pathSeparator}$_configName',
    );
    if (!await config.exists()) return true;
    try {
      final String content = await config.readAsString();
      return !content.contains(subscriptionUrl);
    } catch (_) {
      return true;
    }
  }

  Future<void> _extractBinary() async {
    final String workDir = Directory.current.path;
    final File target = File(
      '$workDir${Platform.pathSeparator}$_binaryName',
    );

    // If already extracted and valid, skip.
    if (await target.exists() && await target.length() > 1000000) {
      _binaryPath = target.path;
      return;
    }

    try {
      final ByteData data = await rootBundle.load('assets/$_binaryName');
      await target.writeAsBytes(
        data.buffer.asUint8List(),
        flush: true,
      );
      _binaryPath = target.path;
    } catch (e) {
      throw Exception('无法解包 mihomo 二进制文件: $e');
    }
  }

  /// Generate a default clash config if none exists.
  Future<void> _ensureConfig() async {
    final String workDir = Directory.current.path;
    _configPath = '$workDir${Platform.pathSeparator}$_configName';

    if (await File(_configPath!).exists()) {
      return;
    }

    const String defaultConfig = '''
# Clash configuration for CyberBangumi Pro
# To activate the proxy, fill in your subscription / node details below.
#
# Quick start:
#   1. Copy this file from %APPDATA%\\clash_win or ~\\.config\\clash
#   2. Or paste your own proxy nodes below

port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: warning

# Replace with your own proxy information.
# Example:
# proxies:
#   - name: "my-proxy"
#     type: ss
#     server: your-server.com
#     port: 443
#     cipher: aes-256-gcm
#     password: "your-password"
#
# proxy-groups:
#   - name: "Proxy"
#     type: select
#     proxies:
#       - my-proxy
#
# rules:
#   - MATCH,Proxy

proxies: []
proxy-groups: []
rules: []
''';

    await File(_configPath!).writeAsString(defaultConfig, flush: true);
  }

  /// Launch the mihomo process.
  Future<void> _spawnProcess() async {
    if (_binaryPath == null || _configPath == null) {
      throw StateError('Clash binary not ready');
    }

    final String workDir = Directory.current.path;
    _process = await Process.start(
      _binaryPath!,
      <String>[
        '-d',  // clash home directory (where config.yaml lives)
        workDir,
        '-f',  // config file path
        _configPath!,
      ],
      workingDirectory: workDir,
      mode: ProcessStartMode.normal,
    );

    // Forward stdout/stderr so it doesn't block the pipe.
    _process!.stdout
        .transform(const SystemEncoding().decoder)
        .listen((String line) {
      // Mihomo outputs startup logs to stdout; suppress in release builds.
    });
    _process!.stderr
        .transform(const SystemEncoding().decoder)
        .listen((String _) {});

    // Detect unexpected exit.
    unawaited(
      _process!.exitCode.then((int code) {
        if (code != 0) {
          _process = null;
        }
      }),
    );
  }

  /// Poll the proxy port until the clash process is ready.
  Future<void> _waitUntilReady() async {
    for (int i = 0; i < _maxHealthCheckAttempts; i++) {
      await Future<void>.delayed(
        Duration(milliseconds: _healthCheckIntervalMs),
      );

      try {
        final Socket socket = await Socket.connect(
          '127.0.0.1',
          7890,
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
        return; // Proxy is ready.
      } catch (_) {
        // Not ready yet, retry.
      }
    }

    throw Exception('Clash 代理进程在 $_maxHealthCheckAttempts 次重试后仍未就绪（端口 7890）');
  }
}
