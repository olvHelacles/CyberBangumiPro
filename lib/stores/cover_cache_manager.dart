import 'dart:io';

import 'package:http/http.dart' as http;

/// 封面图片本地缓存管理器
class CoverCacheManager {
  static const List<String> _knownExtensions = <String>[
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'img',
  ];

  Directory? _cacheDir;

  Directory _resolveCacheBaseDir() {
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
    if (uri == null) return 'img';
    final String path = uri.path.toLowerCase();
    if (path.endsWith('.jpg')) return 'jpg';
    if (path.endsWith('.jpeg')) return 'jpeg';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    return 'img';
  }

  Future<String?> getCachedPath(String subjectId) async {
    if (subjectId.isEmpty) return null;
    final Directory dir = await _ensureCacheDir();

    for (final String ext in _knownExtensions) {
      final File file = File(
        '${dir.path}${Platform.pathSeparator}$subjectId.$ext',
      );
      if (await file.exists()) {
        return file.path;
      }
    }
    return null;
  }

  Future<String?> ensureCached({
    required String subjectId,
    required String imageUrl,
    required Future<http.Response> Function(String url) fetch,
  }) async {
    if (subjectId.isEmpty || imageUrl.isEmpty) return null;

    final String? cached = await getCachedPath(subjectId);
    if (cached != null) return cached;

    final Directory dir = await _ensureCacheDir();
    final String ext = _fileExtFromUrl(imageUrl);
    final File file = File(
      '${dir.path}${Platform.pathSeparator}$subjectId.$ext',
    );

    final http.Response response = await fetch(imageUrl);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;

    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<int> clearAll() async {
    final Directory dir = await _ensureCacheDir();
    if (!await dir.exists()) return 0;

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
