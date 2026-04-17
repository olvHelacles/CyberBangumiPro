import 'package:flutter_test/flutter_test.dart';

import 'package:cyberbangumi_pro/main.dart';

void main() {
  group('BGMLIST schedule parser', () {
    test('parses valid weekly candidate with bangumi id', () {
      final BangumiService service = BangumiService();
      addTearDown(service.dispose);

      final String jsonText = '''
{
  "items": [
    {
      "title": "测试番剧",
      "titleTranslate": {
        "zh-Hans": ["测试番剧中文"]
      },
      "begin": "2026-04-10T15:30:00.000Z",
      "broadcast": "R/2026-04-10T15:30:00.000Z/P7D",
      "images": {
        "common": "https://example.com/cover.jpg"
      },
      "sites": [
        {"site": "bangumi", "id": "123456"}
      ]
    }
  ]
}
''';

      final List<BgmListScheduleCandidate> parsed =
          service.parseBgmListScheduleCandidates(jsonText);

      expect(parsed.length, 1);
      final BgmListScheduleCandidate item = parsed.first;
      expect(item.subjectId, '123456');
      expect(item.subjectUrl, 'https://bangumi.tv/subject/123456');
      expect(item.titleJp, '测试番剧');
      expect(item.titleCn, '测试番剧中文');
      expect(item.coverUrl, 'https://example.com/cover.jpg');
      expect(item.updateTimeJst, '00:30');
      expect(item.periodDays, 7);
      expect(item.weekdayJst, weekdayMap[item.beginJst.weekday]);
    });

    test('drops items without bangumi id', () {
      final BangumiService service = BangumiService();
      addTearDown(service.dispose);

      final String jsonText = '''
{
  "items": [
    {
      "title": "无ID番剧",
      "begin": "2026-04-10T15:30:00.000Z",
      "broadcast": "R/2026-04-10T15:30:00.000Z/P7D",
      "sites": [
        {"site": "anidb", "id": "42"}
      ]
    }
  ]
}
''';

      final List<BgmListScheduleCandidate> parsed =
          service.parseBgmListScheduleCandidates(jsonText);

      expect(parsed, isEmpty);
    });

    test('drops items with non-weekly/monthly period unsupported', () {
      final BangumiService service = BangumiService();
      addTearDown(service.dispose);

      final String jsonText = '''
{
  "items": [
    {
      "title": "月更番剧",
      "begin": "2026-04-10T15:30:00.000Z",
      "broadcast": "R/2026-04-10T15:30:00.000Z/P1M",
      "sites": [
        {"site": "bangumi", "id": "778899"}
      ]
    }
  ]
}
''';

      final List<BgmListScheduleCandidate> parsed =
          service.parseBgmListScheduleCandidates(jsonText);

      expect(parsed, isEmpty);
    });
  });
}
