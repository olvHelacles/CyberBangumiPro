import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Fetches a remote image via a direct (non-proxied) HTTP client with an 8s
/// connection timeout.  On success the image is rendered from memory; on
/// failure or timeout the [fallback] builder is shown.
///
/// This widget deliberately bypasses the Clash proxy — it is intended for
/// user-chosen AppBar background images that are external to the Bangumi
/// domain, so routing them through the proxy provides no benefit.
class AppBarRemoteImage extends StatefulWidget {
  const AppBarRemoteImage({
    super.key,
    required this.uri,
    required this.fit,
    this.cacheWidth,
    required this.fallback,
  });

  final Uri uri;
  final BoxFit fit;
  final int? cacheWidth;
  final WidgetBuilder fallback;

  @override
  State<AppBarRemoteImage> createState() => _AppBarRemoteImageState();
}

class _AppBarRemoteImageState extends State<AppBarRemoteImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final HttpClient client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    // Bypass Clash proxy per design decision — the AppBar background is
    // a user-chosen arbitrary image, not a Bangumi asset.
    client.findProxy = (Uri uri) => 'DIRECT';

    try {
      final HttpClientRequest request = await client.getUrl(widget.uri);
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<int> collected = <int>[];
        await for (final List<int> chunk in response) {
          collected.addAll(chunk);
        }
        final Uint8List bytes = Uint8List.fromList(collected);
        if (mounted) {
          setState(() => _bytes = bytes);
        }
      } else if (mounted) {
        setState(() => _bytes = Uint8List(0)); // mark as failed
      }
    } catch (_) {
      if (mounted) {
        setState(() => _bytes = Uint8List(0)); // mark as failed
      }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.low,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, error, stackTrace) => widget.fallback(context),
      );
    }
    return widget.fallback(context);
  }
}
