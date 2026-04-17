// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:cyberbangumi_pro/main.dart';

/// 测试入口，验证主题映射与主界面基础渲染。
void main() {
  /// 验证时区转换在跨日与偏移边界下行为正确。
  test('Broadcast time conversion handles day carry and offset clamp', () {
    final ConvertedWeekdayTime? converted =
        BroadcastTimeConverter.convertWeekdayAndTime(
      weekday: '星期二',
      time: '00:30',
      fromOffsetMinutes: 9 * 60,
      toOffsetMinutes: 8 * 60,
    );
    expect(converted, isNotNull);
    expect(converted!.weekday, '星期一');
    expect(converted.time, '23:30');

    final ConvertedWeekdayTime? clamped =
        BroadcastTimeConverter.convertWeekdayAndTime(
      weekday: '星期一',
      time: '12:00',
      fromOffsetMinutes: 99999,
      toOffsetMinutes: -99999,
    );
    expect(clamped, isNotNull);
    expect(clamped!.weekday, '星期日');
    expect(clamped.time, '10:00');
  });

  /// 验证按显示时区解析放送时刻时可正确处理 24:xx 跨日时间。
  test('Resolve episode broadcast time supports 24+ hour clock', () {
    final DateTime? displayMoment =
        BroadcastTimeConverter.resolveEpisodeBroadcastInDisplayTime(
      airdateJst: DateTime(2026, 4, 10),
      displayTime: '24:30',
      displayOffsetMinutes: 9 * 60,
    );
    expect(displayMoment, isNotNull);
    expect(displayMoment!.year, 2026);
    expect(displayMoment.month, 4);
    expect(displayMoment.day, 11);
    expect(displayMoment.hour, 0);
    expect(displayMoment.minute, 30);
  });

  /// 验证跨日换算时可按预期更新星期对齐显示时刻。
  test('Resolve episode broadcast time aligns to expected display weekday', () {
    final DateTime? displayMoment =
        BroadcastTimeConverter.resolveEpisodeBroadcastInDisplayTime(
      airdateJst: DateTime(2026, 4, 14),
      displayTime: '23:30',
      displayOffsetMinutes: 8 * 60,
      displayWeekday: '星期一',
    );

    expect(displayMoment, isNotNull);
    expect(displayMoment!.weekday, DateTime.monday);
    expect(displayMoment.hour, 23);
    expect(displayMoment.minute, 30);
  });

  /// 回归测试：周五 20:10 不应把周五 23:00 判定成已放送。
  test('Display timeline ordering does not mark Friday 23:00 as already aired at 20:10', () {
    final DateTime? displayMoment =
        BroadcastTimeConverter.resolveEpisodeBroadcastInDisplayTime(
      airdateJst: DateTime(2026, 4, 17),
      displayTime: '23:00',
      displayOffsetMinutes: 8 * 60,
      displayWeekday: '星期五',
    );

    expect(displayMoment, isNotNull);
    expect(displayMoment!.isUtc, isTrue);
    expect(displayMoment.weekday, DateTime.friday);
    expect(displayMoment.hour, 23);
    expect(displayMoment.minute, 0);

    final DateTime simulatedNowInDisplay = DateTime.utc(2026, 4, 17, 20, 10);
    expect(displayMoment.isAfter(simulatedNowInDisplay), isTrue);
  });

  /// 验证主题模式序列化与反序列化映射稳定。
  test('Theme mode storage mapping is stable', () {
    expect(themeModeFromStorageValue('system'), ThemeMode.system);
    expect(themeModeFromStorageValue('light'), ThemeMode.light);
    expect(themeModeFromStorageValue('dark'), ThemeMode.dark);
    expect(themeModeFromStorageValue('unexpected'), ThemeMode.system);

    expect(themeModeToStorageValue(ThemeMode.system), 'system');
    expect(themeModeToStorageValue(ThemeMode.light), 'light');
    expect(themeModeToStorageValue(ThemeMode.dark), 'dark');
  });

  /// 验证应用主标签页可正常渲染。
  testWidgets('App renders primary tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BangumiHomePage(autoBootstrap: false),
      ),
    );
    await tester.pump();

    expect(find.text('今日更新'), findsOneWidget);
    expect(find.text('我的关注'), findsOneWidget);
    expect(find.text('选择关注'), findsOneWidget);
  });
}
