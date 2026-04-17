# CyberBangumi Pro 项目实现与约定（单文件交接）

本文件用于在新对话窗口中快速恢复项目上下文，覆盖当前实现、约定、数据结构和后续改动注意事项。

## 1. 项目定位

- 技术栈: Flutter + Dart。
- 主要代码入口: lib/main.dart。
- 目标功能:
  - 抓取 Bangumi 日历并展示今日/周历。
  - 维护关注列表。
  - 抓取并展示分集进度、评分、评论热度。
  - 支持手动修正进度并持久化。
  - 支持封面缓存、关注归档、调试工具。

## 2. 运行与依赖

- 关键依赖见 pubspec.yaml:
  - http
  - html
  - url_launcher
  - window_manager
  - flutter_svg
- 运行前建议:
  1. flutter pub get
  2. flutter analyze
  3. flutter test test/widget_test.dart

## 3. 当前架构概览

### 3.1 UI 与状态层

- BangumiApp: 全局主题、字体、AppBar/TabBar 风格。
- BangumiHomePage + _BangumiHomePageState: 主状态机，包含四个页签:
  - 今日更新
  - 我的关注
  - 番剧周历
  - 选择关注
- AppBar 标题区已改为 Logo 图层方案:
  - 通过 _buildAppBarBottom() 返回 PreferredSizeWidget，修复 AppBar.bottom 类型要求。
  - TabBar 作为底层，Logo 通过 Stack + Positioned 叠放在 TabBar 上方。
  - Logo 资源已切换为 SVG（assets/images/logoWHT.svg）。
  - Logo 可调参数集中在 _BangumiHomePageState 顶部常量:
    - _appBarLogoWidth / _appBarLogoHeight
    - _appBarLogoOpacity
    - _appBarLogoOffsetX / _appBarLogoOffsetY
    - _appBarLogoGapAboveTabBar
    - _appBarLogoAlignment / _appBarLogoPadding

### 3.2 数据模型

- SubjectItem: 条目基础信息（id、名称、链接、封面、更新时间、本地封面路径）。
- DaySchedule: 周几 -> 条目列表。
- SubjectProgress: 进度、评分、评论、每集标题映射等。
- WatchArchiveEntry: 归档实体。

### 3.3 存储与缓存组件

- CoverCacheManager:
  - 目录: 项目根/cover_cache。
  - 作用: 封面落盘、查找、清理。
- CalendarCacheManager:
  - 文件: 项目根/calendar_cache.json。
  - 作用: 日历缓存。
- AppStateStore:
  - 文件: 项目根/app_state.json。
  - 作用: 统一保存设置、关注列表、进度修正、自动刷新月标记。
- WatchArchiveStore:
  - 文件: 项目根/watch_archive.json。
  - 作用: 关注归档增量写入与读取。

### 3.4 服务层

- BangumiService:
  - 统一网络重试、请求节流、日志回调。
  - API 进度来源: Bangumi API（不再走 HTML 进度兜底）。
  - 日历来源: Bangumi 日历页面解析。
  - 时间补全来源: BGMLIST + YUC（名称匹配）。

## 4. 关键业务流程

### 4.1 启动流程

_bootstrap 顺序:
1. 读设置 _loadSettings。
2. 读手动修正 _loadProgressCorrections。
3. 读关注列表 _loadWatchlist。
4. 刷新日历 _refreshCalendarSchedule(initial: true)。
5. 刷新进度 _refreshProgressFromMainAction。

### 4.2 日历刷新

- 支持本地缓存优先，必要时网络刷新。
- 每月 1 号可自动触发一次网络刷新（通过 calendar_auto_refresh_month 标记）。
- 刷新后调用 _archiveMissingWatchlistItemsAfterCalendar:
  - 若关注条目不在当前日历中，自动从关注移除并写入归档。
  - 若当前日历抓取结果为空，触发保护逻辑，不做批量移除。

### 4.3 进度刷新

- _refreshProgress 支持全量或仅针对新增关注条目。
- 并发受设置项 progress_concurrency 控制。
- 最新已放送集数判定支持放送时刻精度：若已知放送时刻，则按“当前时刻 >= 放送时刻”判定是否已放送。
- 刷新后会应用 _applyManualProgressCorrection 覆盖展示值。

### 4.3.1 时区转换

- 设置项支持“转换时区”（开关）与“目标时区”（固定 UTC 偏移，默认 UTC+8）。
- 关闭转换时使用 JST（UTC+9）。
- 开启转换后，日历中的放送星期与时刻会按目标时区重算并展示。
- 每日放送、关注页、周历中的日期/时刻标签会显示当前时区信息。

### 4.4 手动修正进度

- 入口: 关注页卡片按钮 修正更新进度。
- 数据:
  - progress_correction_deltas_v1（subject_id -> delta_ep）。
  - 兼容历史 progress_corrections_v1（subject_id -> corrected_ep），会在刷新时迁移为 delta。
- 展示规则:
  - 理论进度来自 API（theoretical_ep）。
  - 实际展示进度 = clamp(theoretical_ep + delta_ep, 0..totalEps)。
  - 优先使用 episodeTitleByEp[展示集数] 显示分集标题。
  - 若没有映射且展示集数等于理论最新集，退回 latestAiredCnTitle。

### 4.5 关注与取消关注

- 今日页、周历封面右上角按钮共用关注逻辑。
- 新增关注: 写入 watchlist，并只刷新该条目进度。
- 取消关注: 从 watchlist 和 selectedIds 移除，同时清理 progressCache 与对应修正数据。

### 4.6 周历展示

- _weekCalendarShowAll 开关:
  - false: 仅显示已关注。
  - true: 显示当期全部。
- 横向滚动展示周一到周日列。
- 外层支持纵向滚动，避免内容溢出。

### 4.7 外链打开

- 点击今日/关注/周历封面可打开 Bangumi 页面。
- 策略:
  1. url_launcher 外部应用模式。
  2. 失败时按系统命令兜底（Windows: cmd /c start，macOS: open，Linux: xdg-open）。

## 5. 持久化结构约定

### 5.1 app_state.json

顶层为对象，当前使用键:

- watchlist: List<SubjectItem>
- app_settings_v1: 设置对象
- progress_corrections_v1: Map<String, int>（历史绝对集数，兼容读取）
- progress_correction_deltas_v1: Map<String, int>（当前使用，修正偏移）
- calendar_auto_refresh_month: String，格式 yyyy-MM

app_settings_v1 当前字段:

- progress_concurrency: int，范围 1..30
- cover_cache_concurrency: int，范围 1..24
- api_user_agent: String
- theme_mode_v1: String，取值 system/light/dark，默认 system（跟随系统）
- appbar_background_image_enabled: bool，默认 false（亮色/深色模式均可生效）
- appbar_background_image_path: String，背景图路径，支持 assets/、本地绝对路径、http(s)
- timezone_conversion_enabled: bool，默认 true
- timezone_offset_minutes: int，范围 -720..840，默认 480（UTC+8）

### 5.2 watch_archive.json

- 数组，每项字段:
  - subject_id
  - name_cn
  - name_jp
  - quarter
  - text
  - archived_at

### 5.3 calendar_cache.json

- 数组，每项为 DaySchedule:
  - weekday
  - items (SubjectItem 列表)

## 6. 重要约定与不变量

1. 所有业务数据持久化都在项目根目录（Directory.current）。
2. API UA 与页面抓取 UA 分离:
   - API 请求头使用可配置 api_user_agent。
   - 页面抓取和图片请求固定 browserUserAgent，不受设置影响。
3. 已放送判定基于 airdate，不使用评论阈值。
4. 进度来源优先 Bangumi API；若 API 无有效数据，当前实现直接报错而非 HTML 兜底。
5. 周历封面回填必须同步更新 _scheduleData，否则周历无法显示本地缓存封面。
6. 涉及关注移除时要同步清理:
   - _selectedIds
   - _progressCache
   - _manualProgressCorrections

## 7. 调试能力

- 顶部 调试工具 提供:
  - 日志窗口（含网络/状态日志）
  - 调试今日星期
  - 悬停命中区域可视化（评论热度图）
  - 调试归档当前关注（立即把当前关注写入归档，不移除关注）

## 8. 近期改动焦点（已落地）

- 修正进度按钮可见性与布局修复。
- 手动修正后分集标题精确显示（ep -> title 映射）。
- 封面点击外跳与失败兜底修复。
- 移除评论阈值设置和相关旧逻辑。
- SharedPreferences 持久化迁移为项目根 app_state.json。
- 周历新增全量显示开关与封面角标关注按钮。
- 新增关注归档（自动归档 + 调试强制归档）。
- API UA 可通过 app_state.json 设置，不影响页面抓取 UA。
- 新增时区转换设置（开关 + 目标时区），并在日期/时刻标签显示当前时区。
- 最新已放送集数判定升级为时刻精度，并显示“最新已放送”对应时刻标签。
- AppBar 标题文字“CyberBangumi Pro”已替换为可调位置/透明度的 Logo 图层。
- Logo 资源从 PNG 升级为 SVG 渲染，降低放大时锯齿风险。
- 已补充 Logo 横向偏移参数 _appBarLogoOffsetX，用于在 padding 到极限后继续向左微调。
- 新增主题模式设置（跟随系统/亮色/深色），写入 app_settings_v1.theme_mode_v1。
- 关键卡片、徽标、周历角标与调试覆盖层颜色已改为基于 ColorScheme，深色模式下可读性对齐。
- 已新增 AppBar/TabBar 自定义背景图支持（亮色/深色模式），通过 app_settings_v1 读取开关与路径。
- AppBar Bottom 已改为“仅裁剪底边”，确保 Logo 溢出到主页面区域时被裁掉，同时保留向上层叠效果。
- AppBar 背景图加载已做防阻塞加固：限制解码尺寸（cacheWidth/cacheHeight）、异常路径自动回退、UNC 网络共享路径默认禁用加载。
- 周历网络源已切换为 BGMLIST 直连链路（不再依赖 bangumi.tv/calendar 页面抓取）：
  - 从 BGMLIST `sites` 直接提取 bangumi id，缺失则丢弃。
  - 从 `begin` + `broadcast` 解析 JST 星期与更新时间。
  - 当期判定按“begin + Bangumi API 总集数 + broadcast 周期”计算，且不使用 BGMLIST `end` 字段。
  - BGMLIST 网络失败时回退本地 `calendar_cache.json`（不回退 calendar 页面抓取）。

## 9. 后续改动清单（建议每次改动自查）

1. 修改持久化字段时，同时更新读取默认值和写回逻辑。
2. 修改关注逻辑时，检查是否同步清理进度缓存和手动修正。
3. 修改周历/今日封面来源时，检查 _scheduleData、_todayItems、_watchlist 是否一致更新。
4. 修改进度逻辑时，验证手动修正覆盖是否仍生效。
5. 修改网络头时，确认 API 与页面抓取 UA 的隔离未被破坏。
6. 提交前至少执行 flutter analyze 与目标测试。
7. 修改视觉颜色时，优先使用 ColorScheme 语义色，避免回退为固定亮色常量。

## 10. 新会话接力模板

可将下面文本直接发给新对话窗口:

请先阅读项目根目录的 PROJECT_HANDOFF.md，然后在不改变既有约定的前提下继续开发。
必须遵守:
1. 业务数据持久化保持在项目根目录。
2. API UA 可配置，但页面抓取与图片请求继续使用固定 browserUserAgent。
3. 手动修正进度逻辑不得回退，修正后标题优先按分集映射显示。
4. 修改关注/周历逻辑时保证 _scheduleData 与缓存回填一致。
