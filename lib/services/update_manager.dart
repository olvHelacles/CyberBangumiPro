import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Result of a version check against GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
    required this.hasUpdate,
  });

  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;
  final bool hasUpdate;
}

/// Checks for new releases on GitHub, downloads the update ZIP, and applies
/// it by launching an external updater script.
class UpdateManager {
  static const String _repoOwner = 'olvHelacles';
  static const String _repoName = 'CyberBangumiPro';
  static const String _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const String _exeName = 'cyber_bangumi_pro.exe';

  /// Fetch the latest release info from GitHub API.
  /// Returns null on network error or parse failure.
  static Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    final HttpClient client = HttpClient();
    client.userAgent = 'CyberBangumiPro/$currentVersion';
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(_apiUrl));
      req.headers.set('Accept', 'application/json');
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final String body =
          await resp.transform(utf8.decoder).join();
      final Map<String, dynamic> data =
          jsonDecode(body) as Map<String, dynamic>;
      final String tag =
          (data['tag_name'] as String?) ?? '';
      if (tag.isEmpty) return null;

      final List<dynamic> assets = data['assets'] as List<dynamic>? ?? <dynamic>[];
      String downloadUrl = '';
      for (final dynamic asset in assets) {
        if (asset is Map<String, dynamic>) {
          final String name = (asset['name'] as String?) ?? '';
          if (name.endsWith('-windows-x64.zip')) {
            downloadUrl = (asset['browser_download_url'] as String?) ?? '';
            break;
          }
        }
      }
      if (downloadUrl.isEmpty) return null;

      final String? notes = data['body'] as String?;
      return UpdateInfo(
        latestVersion: tag,
        downloadUrl: downloadUrl,
        releaseNotes: notes,
        hasUpdate: _isNewerVersion(currentVersion, tag),
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Download the release ZIP to the system temp directory.
  /// Returns the local file path.
  static Future<String> downloadUpdate(String url) async {
    final String tempDir = Directory.systemTemp.path;
    final String zipPath = '$tempDir${Platform.pathSeparator}cyberbangumi_update.zip';

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(url));
      final HttpClientResponse resp = await req.close();
      final Uint8List bytes = await resp.fold<Uint8List>(
        Uint8List(0),
        (Uint8List prev, List<int> chunk) {
          final Uint8List combined = Uint8List(prev.length + chunk.length);
          combined.setRange(0, prev.length, prev);
          combined.setRange(prev.length, combined.length, chunk);
          return combined;
        },
      );
      await File(zipPath).writeAsBytes(bytes, flush: true);
      return zipPath;
    } finally {
      client.close();
    }
  }

  /// Extract the ZIP via PowerShell and launch an updater batch script.
  /// The updater waits for the current process to exit, copies the new
  /// files over the old ones, then restarts the app.
  static Future<void> applyUpdate(String zipPath) async {
    final String tempDir = Directory.systemTemp.path;
    final String extractDir = '$tempDir${Platform.pathSeparator}cyberbangumi_update';
    final String appDir = Directory.current.path;

    // Extract ZIP using PowerShell Expand-Archive.
    await Process.run(
      'powershell',
      <String>[
        '-NoProfile',
        '-Command',
        'Expand-Archive',
        '-Path',
        '"$zipPath"',
        '-DestinationPath',
        '"$extractDir"',
        '-Force',
      ],
    );

    // Generate updater batch script.
    final String batPath = '$tempDir${Platform.pathSeparator}cyberbangumi_updater.bat';
    final String batContent = '''@echo off
chcp 65001 >nul
set "APP_DIR=$appDir"
set "UPDATE_DIR=$extractDir"
:RECHECK
"%SYSTEMROOT%\\system32\\tasklist.exe" /FI "IMAGENAME eq $_exeName" 2>NUL | "%SYSTEMROOT%\\system32\\find.exe" /I /C "$_exeName" >NUL
if not errorlevel 1 (
    "%SYSTEMROOT%\\system32\\timeout.exe" /t 1 /nobreak >NUL
    goto RECHECK
)
xcopy /E /Y /Q "%UPDATE_DIR%\\*" "%APP_DIR%\\"
start "" "%APP_DIR%\\$_exeName"
del "%~f0"
''';

    await File(batPath).writeAsString(batContent, flush: true);

    // Launch the updater (detached, hidden) and exit the app.
    await Process.start(
      'cmd',
      <String>['/c', 'start', '', '/MIN', '"CyberBangumi Updater"', batPath],
      runInShell: true,
    );

    // Give the updater a moment to start, then signal the app to exit.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  /// Compare two version strings (e.g. "v0.7.0", "0.6.1").
  /// Returns true when [latest] is strictly newer than [current].
  static bool _isNewerVersion(String current, String latest) {
    final List<int> cur = _parseVersion(current);
    final List<int> lat = _parseVersion(latest);
    for (int i = 0; i < 3; i++) {
      final int c = i < cur.length ? cur[i] : 0;
      final int l = i < lat.length ? lat[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// Parse "v0.7.0" → [0, 7, 0]; "0.6.1" → [0, 6, 1].
  static List<int> _parseVersion(String v) {
    final String cleaned = v.startsWith('v') ? v.substring(1) : v;
    return cleaned
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
  }
}
