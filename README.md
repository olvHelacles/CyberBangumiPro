<img alt="Cover" src="./docs/imgs/logo.png" width = "512">

CyberBangumi Pro 是一个基于 Flutter 的番剧日历与追番辅助工具，聚焦以下目标：

- 自动抓取 Bangumi 周历数据
- 结合 BGMLIST OnAir JSON 补全放送时刻
- 管理关注列表并刷新每部番剧的放送进度
- 支持时区转换，便于按本地时区查看放送信息

## 核心功能

### 1. 日历抓取与时刻补全

- 从 Bangumi 日历页面抓取每周放送条目
- 通过 BGMLIST API 返回的 OnAir JSON 做日文模糊匹配，补全每个条目的更新时间

### 2. 多标签浏览

应用包含四个主要标签页：

- 今日更新：展示当天番剧，支持快速关注/取消关注
- 我的关注：集中查看已关注番剧及进度
- 番剧周历：按星期网格查看放送分布(精确放送时刻仅供参考)
- 选择关注：筛选并批量保存关注对象

### 3. 进度刷新

- 基于 Bangumi API 拉取分集与条目信息
- 支持并发刷新，提高关注列表批量更新速度
- 支持手动进度修正

### 4. 缓存与本地存储

- 封面缓存目录：cover_cache/
- 日历缓存文件：calendar_cache.json
- 应用状态文件：app_state.json
- 关注归档文件：watch_archive.json

## 数据来源

- Bangumi 日历页：https://bangumi.tv/calendar
- Bangumi API：https://api.bgm.tv
- BGMLIST OnAir API：https://bgmlist.com/api/v1/bangumi/onair

## 时区说明

- 默认使用时区转换（默认 UTC+8）
- 可在设置中开关时区转换并调整偏移
- 日历缓存会绑定时区配置；配置变化后会自动重新抓取并重算显示结果

## 运行与开发

### 环境要求

- Flutter SDK 3.10+
- Dart SDK 3.10+
- 建议在 Windows 桌面环境下运行与调试

### 启动步骤

```bash
flutter pub get
flutter run -d windows
```

如需在其他平台运行，可替换对应设备参数。

### 测试

```bash
flutter test test/widget_test.dart
```

## 项目结构（简要）

- lib/main.dart：主要业务逻辑与界面实现
- test/widget_test.dart：基础行为测试
- assets/images/：图标、Logo 等资源
- assets/fonts/：字体资源

