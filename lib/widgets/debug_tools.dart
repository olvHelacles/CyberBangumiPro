import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/simulated_anime.dart';
import '../models/subject_item.dart';
import '../models/watch_archive_entry.dart';
import '../stores/watch_archive_store.dart';

/// 调试工具集合：日志窗口、星期调试、关注归档调试。
class DebugTools {
  /// 打开调试工具底部弹窗。
  static Future<void> showTools({
    required BuildContext context,
    required List<String> debugLogs,
    required int? debugWeekdayOverride,
    required bool debugShowChartHoverHitArea,
    required String systemWeekday,
    required List<SubjectItem> watchlist,
    required WatchArchiveStore watchArchiveStore,
    required String currentQuarterLabel,
    required ValueChanged<int?> onApplyWeekdayOverride,
    required VoidCallback onClearLogs,
    required VoidCallback onArchiveWatchlist,
    required VoidCallback onToggleHoverHitArea,
    required void Function(String) showStatus,
    required void Function(String) appendDebugLog,
    required Future<void> Function() openLogDialog,
    required Future<void> Function() openWeekdayDialog,
    VoidCallback? onCreateSimulatedAnime,
  }) async {
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
                subtitle: const Text('指定程序中的"今日"星期值'),
                onTap: () => Navigator.of(context).pop('weekday'),
              ),
              ListTile(
                leading: Icon(
                  debugShowChartHoverHitArea
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                title: const Text('悬停判定区域可视化'),
                subtitle: Text(
                  debugShowChartHoverHitArea ? '当前: 已开启' : '当前: 已关闭',
                ),
                onTap: () => Navigator.of(context).pop('hover-hit-area'),
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('调试：归档当前关注'),
                subtitle: const Text('立即将当前关注番剧写入关注归档'),
                onTap: () =>
                    Navigator.of(context).pop('archive-current-watch'),
              ),
              if (onCreateSimulatedAnime != null)
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('调试：创建模拟番剧'),
                  subtitle: const Text('创建可控的测试番剧用于调试追番排序'),
                  onTap: () =>
                      Navigator.of(context).pop('create-simulated-anime'),
                ),
            ],
          ),
        );
      },
    );

    if (action == null) return;

    switch (action) {
      case 'logs':
        appendDebugLog('已打开日志窗口');
        await openLogDialog();
      case 'weekday':
        await openWeekdayDialog();
      case 'archive-current-watch':
        await _archiveCurrentWatchlistForDebug(
          watchlist: watchlist,
          watchArchiveStore: watchArchiveStore,
          currentQuarterLabel: currentQuarterLabel,
          showStatus: showStatus,
          appendDebugLog: appendDebugLog,
        );
      case 'hover-hit-area':
        onToggleHoverHitArea();
        showStatus(
          debugShowChartHoverHitArea
              ? '已关闭悬停判定区域可视化'
              : '已开启悬停判定区域可视化',
        );
      case 'create-simulated-anime':
        onCreateSimulatedAnime?.call();
    }
  }

  static Future<void> _archiveCurrentWatchlistForDebug({
    required List<SubjectItem> watchlist,
    required WatchArchiveStore watchArchiveStore,
    required String currentQuarterLabel,
    required void Function(String) showStatus,
    required void Function(String) appendDebugLog,
  }) async {
    final List<SubjectItem> targets = watchlist
        .where((SubjectItem item) => item.subjectId.isNotEmpty)
        .toList();
    if (targets.isEmpty) {
      showStatus('调试归档：当前没有可归档的关注番剧');
      return;
    }

    final List<WatchArchiveEntry> entries = targets
        .map((SubjectItem item) =>
            WatchArchiveEntry.fromSubject(item, quarter: currentQuarterLabel))
        .toList();
    await watchArchiveStore.appendEntries(entries);
    appendDebugLog('调试归档：已写入 ${entries.length} 条关注归档记录');
    showStatus('调试归档完成：已加入 ${entries.length} 部番剧');
  }

  /// 打开日志查看弹窗。
  static Future<void> showLogDialog({
    required BuildContext context,
    required List<String> debugLogs,
    required VoidCallback onClearLogs,
    required void Function(String) appendDebugLog,
  }) async {
    final String logText = debugLogs.isEmpty
        ? '暂无日志输出。'
        : debugLogs.join('\n');

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
                onClearLogs();
                appendDebugLog('日志已手动清空');
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

  /// 打开星期调试弹窗。
  static Future<int?> showWeekdayDialog({
    required BuildContext context,
    required int? debugWeekdayOverride,
    required String systemWeekday,
    required ValueChanged<int?> onApply,
  }) async {
    final int? selected = await showDialog<int?>(
      context: context,
      builder: (BuildContext context) {
        int? tempValue = debugWeekdayOverride;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            final List<DropdownMenuItem<int?>> options =
                <DropdownMenuItem<int?>>[
              DropdownMenuItem<int?>(
                value: null,
                child: Text('系统时间（当前：$systemWeekday）'),
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
                    labelText: '程序中"今日"对应星期',
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

    return selected;
  }

  /// Shows a dialog for creating a new SimulatedAnime for debugging.
  /// Returns the created SimulatedAnime, or null if cancelled.
  static Future<SimulatedAnime?> showSimulatedAnimeCreator(
    BuildContext context,
  ) async {
    String title = '【调试】测试番剧';
    String weekday = '星期一';
    final TextEditingController timeCtrl = TextEditingController(text: '22:30');
    final TextEditingController totalCtrl = TextEditingController(text: '12');
    final TextEditingController delayCtrl = TextEditingController(text: '5');
    final TextEditingController intervalCtrl = TextEditingController(text: '7');
    DateTime firstDate = DateTime.now();

    return showDialog<SimulatedAnime>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('创建模拟番剧'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '标题',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: TextEditingController(text: title),
                      onChanged: (v) => title = v,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: weekday,
                      decoration: const InputDecoration(
                        labelText: '放送星期',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: <String>[
                        '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
                      ].map((w) => DropdownMenuItem<String>(
                        value: w, child: Text(w),
                      )).toList(),
                      onChanged: (v) {
                        if (v != null) setLocalState(() => weekday = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '放送时刻（如 22:00）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: timeCtrl,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '首集放送日期',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                      controller: TextEditingController(
                        text:
                            '${firstDate.year}-${firstDate.month.toString().padLeft(2, '0')}-${firstDate.day.toString().padLeft(2, '0')}',
                      ),
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: firstDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setLocalState(() => firstDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '总集数',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: totalCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'API 更新延迟（分钟）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: delayCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '集数间隔（天）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: intervalCtrl,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final RegExpMatch? timeMatch = RegExp(
                      r'^(\d{1,2}):(\d{2})$',
                    ).firstMatch(timeCtrl.text.trim());
                    if (timeMatch == null) return;
                    final int total = int.tryParse(totalCtrl.text) ?? 0;
                    if (total <= 0) return;
                    final int delay = int.tryParse(delayCtrl.text) ?? 5;
                    final int interval = int.tryParse(intervalCtrl.text) ?? 7;
                    final int nextId = DateTime.now().millisecondsSinceEpoch % 100000;
                    Navigator.of(context).pop(SimulatedAnime(
                      subjectId: 'debug_${nextId}_${DateTime.now().second}',
                      title: title,
                      weekdayJst: weekday,
                      broadcastTimeJst: timeCtrl.text.trim(),
                      firstEpisodeAirdate: firstDate,
                      totalEpisodes: total,
                      apiUpdateDelayMinutes: delay,
                      episodeIntervalDays: interval,
                    ));
                  },
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
