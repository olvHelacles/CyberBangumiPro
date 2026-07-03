import 'package:flutter/material.dart';

import '../clash_manager.dart';
import '../models/broadcast_types.dart';

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

/// Display text for a [ThemeMode] value (Chinese labels).
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

int _clampProgressConcurrency(int value) => value.clamp(1, 30);
int _clampCoverCacheConcurrency(int value) => value.clamp(1, 24);
int _clampTimezoneOffsetMinutes(int value) =>
    BroadcastTimeConverter.normalizeTimezoneOffsetMinutes(value);

// ---------------------------------------------------------------------------
// SettingsData – value object bundling all settings fields
// ---------------------------------------------------------------------------

/// Immutable snapshot of the settings edited in [SettingsDialog].
class SettingsData {
  final int progressConcurrency;
  final int coverCacheConcurrency;
  final String apiUserAgent;
  final ThemeMode themeMode;
  final bool appBarBackgroundImageEnabled;
  final String appBarBackgroundImagePath;
  final bool timezoneConversionEnabled;
  final int timezoneOffsetMinutes;
  final bool proxyEnabled;
  final String proxySubscriptionUrl;

  const SettingsData({
    required this.progressConcurrency,
    required this.coverCacheConcurrency,
    required this.apiUserAgent,
    required this.themeMode,
    required this.appBarBackgroundImageEnabled,
    required this.appBarBackgroundImagePath,
    required this.timezoneConversionEnabled,
    required this.timezoneOffsetMinutes,
    required this.proxyEnabled,
    required this.proxySubscriptionUrl,
  });

  SettingsData copyWith({
    int? progressConcurrency,
    int? coverCacheConcurrency,
    String? apiUserAgent,
    ThemeMode? themeMode,
    bool? appBarBackgroundImageEnabled,
    String? appBarBackgroundImagePath,
    bool? timezoneConversionEnabled,
    int? timezoneOffsetMinutes,
    bool? proxyEnabled,
    String? proxySubscriptionUrl,
  }) {
    return SettingsData(
      progressConcurrency: progressConcurrency ?? this.progressConcurrency,
      coverCacheConcurrency: coverCacheConcurrency ?? this.coverCacheConcurrency,
      apiUserAgent: apiUserAgent ?? this.apiUserAgent,
      themeMode: themeMode ?? this.themeMode,
      appBarBackgroundImageEnabled:
          appBarBackgroundImageEnabled ?? this.appBarBackgroundImageEnabled,
      appBarBackgroundImagePath:
          appBarBackgroundImagePath ?? this.appBarBackgroundImagePath,
      timezoneConversionEnabled:
          timezoneConversionEnabled ?? this.timezoneConversionEnabled,
      timezoneOffsetMinutes: timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      proxySubscriptionUrl: proxySubscriptionUrl ?? this.proxySubscriptionUrl,
    );
  }
}

// ---------------------------------------------------------------------------
// SettingsDialog
// ---------------------------------------------------------------------------

class SettingsDialog extends StatefulWidget {
  final SettingsData initialData;
  final List<int> commonTimezoneOffsets;
  final VoidCallback onOpenWatchArchive;
  final VoidCallback onClearCoverCache;

  const SettingsDialog({
    super.key,
    required this.initialData,
    required this.commonTimezoneOffsets,
    required this.onOpenWatchArchive,
    required this.onClearCoverCache,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late int _tempProgressConcurrency;
  late int _tempCoverCacheConcurrency;
  late String _tempApiUserAgent;
  late ThemeMode _tempThemeMode;
  late bool _tempAppBarBackgroundImageEnabled;
  late String _tempAppBarBackgroundImagePath;
  late bool _tempTimezoneConversionEnabled;
  late int _tempTimezoneOffsetMinutes;
  late bool _tempProxyEnabled;
  late String _tempProxySubscriptionUrl;
  late TextEditingController _subscriptionCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _tempProgressConcurrency = d.progressConcurrency;
    _tempCoverCacheConcurrency = d.coverCacheConcurrency;
    _tempApiUserAgent = d.apiUserAgent;
    _tempThemeMode = d.themeMode;
    _tempAppBarBackgroundImageEnabled = d.appBarBackgroundImageEnabled;
    _tempAppBarBackgroundImagePath = d.appBarBackgroundImagePath;
    _tempTimezoneConversionEnabled = d.timezoneConversionEnabled;
    _tempTimezoneOffsetMinutes = d.timezoneOffsetMinutes;
    _tempProxyEnabled = d.proxyEnabled;
    _tempProxySubscriptionUrl = d.proxySubscriptionUrl;
    _subscriptionCtrl = TextEditingController(text: d.proxySubscriptionUrl);
  }

  @override
  void dispose() {
    _subscriptionCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop(SettingsData(
      progressConcurrency: _tempProgressConcurrency,
      coverCacheConcurrency: _tempCoverCacheConcurrency,
      apiUserAgent: _tempApiUserAgent,
      themeMode: _tempThemeMode,
      appBarBackgroundImageEnabled: _tempAppBarBackgroundImageEnabled,
      appBarBackgroundImagePath: _tempAppBarBackgroundImagePath,
      timezoneConversionEnabled: _tempTimezoneConversionEnabled,
      timezoneOffsetMinutes: _tempTimezoneOffsetMinutes,
      proxyEnabled: _tempProxyEnabled,
      proxySubscriptionUrl: _tempProxySubscriptionUrl,
    ));
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ── Theme mode ──
              DropdownButtonFormField<ThemeMode>(
                initialValue: _tempThemeMode,
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
                  if (value == null) return;
                  setState(() {
                    _tempThemeMode = value;
                  });
                },
              ),
              const Divider(height: 24),

              // ── AppBar background image ──
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _tempAppBarBackgroundImageEnabled,
                onChanged: (bool value) {
                  setState(() {
                    _tempAppBarBackgroundImageEnabled = value;
                  });
                },
                title: const Text('启用 AppBar 背景图'),
                subtitle: const Text('可填本地路径或 http(s) 地址'),
              ),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: _tempAppBarBackgroundImagePath,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'AppBar/TabBar 背景图路径',
                  hintText:
                      '例如 assets/images/appbar_bg.png 或 C:/path/bg.png',
                ),
                onChanged: (String value) {
                  setState(() {
                    _tempAppBarBackgroundImagePath = value.trim();
                  });
                },
              ),
              const Divider(height: 24),

              // ── Progress concurrency ──
              Align(
                alignment: Alignment.centerLeft,
                child: Text('进度刷新并发: $_tempProgressConcurrency'),
              ),
              Slider(
                min: 1,
                max: 30,
                divisions: 29,
                value: _tempProgressConcurrency.toDouble(),
                label: '$_tempProgressConcurrency',
                onChanged: (double value) {
                  setState(() {
                    _tempProgressConcurrency =
                        _clampProgressConcurrency(value.round());
                  });
                },
              ),

              // ── Cover cache concurrency ──
              Align(
                alignment: Alignment.centerLeft,
                child: Text('封面缓存并发: $_tempCoverCacheConcurrency'),
              ),
              Slider(
                min: 1,
                max: 24,
                divisions: 23,
                value: _tempCoverCacheConcurrency.toDouble(),
                label: '$_tempCoverCacheConcurrency',
                onChanged: (double value) {
                  setState(() {
                    _tempCoverCacheConcurrency =
                        _clampCoverCacheConcurrency(value.round());
                  });
                },
              ),
              const Divider(height: 24),

              // ── Timezone conversion ──
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _tempTimezoneConversionEnabled,
                onChanged: (bool value) {
                  setState(() {
                    _tempTimezoneConversionEnabled = value;
                  });
                },
                title: const Text('转换时区'),
                subtitle: Text(
                  _tempTimezoneConversionEnabled
                      ? '已开启，当前目标 ${BroadcastTimeConverter.formatUtcOffsetLabel(_tempTimezoneOffsetMinutes)}'
                      : '已关闭，按 JST 显示',
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: _tempTimezoneOffsetMinutes,
                decoration: const InputDecoration(
                  labelText: '目标时区（固定选项）',
                  border: OutlineInputBorder(),
                ),
                items: widget.commonTimezoneOffsets
                    .map(
                      (int offset) => DropdownMenuItem<int>(
                        value: offset,
                        child: Text(
                          BroadcastTimeConverter.formatUtcOffsetLabel(offset),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _tempTimezoneConversionEnabled
                    ? (int? value) {
                        if (value == null) return;
                        setState(() {
                          _tempTimezoneOffsetMinutes =
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
                      setState(() {});
                      try {
                        await ClashManager.instance.stop();
                        await ClashManager.instance.start();
                        await ClashManager.instance.refreshNodeInfo();
                        setState(() {});
                      } catch (e) {
                        setState(() {});
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
                controller: _subscriptionCtrl,
                enableInteractiveSelection: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Clash 订阅链接',
                  hintText: 'https://your-subscription-url',
                ),
                onChanged: (String value) {
                  setState(() {
                    _tempProxySubscriptionUrl = value.trim();
                  });
                },
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _tempProxyEnabled,
                onChanged: (bool value) {
                  setState(() {
                    _tempProxyEnabled = value;
                  });
                },
                title: const Text('启用代理'),
                subtitle: const Text('127.0.0.1:7890（内建 Clash）'),
              ),
              const Divider(height: 24),

              // ── API User-Agent ──
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Bangumi API UA'),
              ),
              const SizedBox(height: 5),
              TextFormField(
                initialValue: _tempApiUserAgent,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '用于 Bangumi API 请求的 User-Agent',
                ),
                onChanged: (String value) {
                  setState(() {
                    _tempApiUserAgent = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: () => widget.onOpenWatchArchive(),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('关注归档'),
        ),
        TextButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onClearCoverCache();
          },
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('清除封面缓存'),
        ),
        TextButton(
          onPressed: _cancel,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
