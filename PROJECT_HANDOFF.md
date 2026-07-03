# CyberBangumi Pro v0.6.1 项目实现与约定（单文件交接）

本文件用于在新对话窗口中快速恢复项目上下文，覆盖当前实现、约定、数据结构和后续改动注意事项。

## 1. 项目定位

- 技术栈: Flutter + Dart。
- 主要代码入口: lib/main.dart、lib/clash_manager.dart。
- 目标功能:
  - 从 bgmlist.com/archive 抓取当季番剧并展示今日/周历。
  - 基于 BGMLIST OnAir API 补充半年番，通过 Bangumi API 验证播出进度。
  - 维护关注列表。
  - 抓取并展示分集进度、评分、评论热度。
  - 支持手动修正进度并持久化。
  - 支持封面缓存、关注归档、调试工具。
  - 内建 Clash (mihomo) 代理，解决 Bangumi API 网络可达性问题。
  - Bangumi API 条目搜索（番剧搜索 Tab）。
  - 条目详情弹窗（评分分布柱状图、制作信息、简介）。

## 2. 运行与依赖

- 关键依赖见 pubspec.yaml:
  - http, html, url_launcher, window_manager, flutter_svg
- API 参考文档: docs/v0.yaml（Bangumi OpenAPI 规范）
- Clash 核心: assets/mihomo.exe（v1.19.27，~45MB）
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
  - 番剧搜索
- AppBar 标题区为 Logo 图层方案，SVG 渲染。
- 条目详情弹窗: showModalBottomSheet + DraggableScrollableSheet，展示评分分布柱状图、制作信息、可展开简介。

### 3.2 数据模型

- SubjectItem: 条目基础信息（id、名称、链接、封面、更新时间、本地封面路径）。
- DaySchedule: 周几 -> 条目列表。
- SubjectProgress: 进度、评分、评论、每集标题映射、latestAiredAt（最新放送时间 DateTime，用于排序）等。
- WatchArchiveEntry: 归档实体。
- SearchSubjectResult: 搜索结果（SubjectItem + ratingScore + airDate + popularity）。
- SearchSubjectsResponse: 搜索结果分页包装（total + results）。

### 3.3 存储与缓存组件

- CoverCacheManager: 项目根/cover_cache。
- CalendarCacheManager: 项目根/calendar_cache.json。
- AppStateStore: 项目根/app_state.json。
- WatchArchiveStore: 项目根/watch_archive.json。

### 3.4 服务层

- BangumiService:
  - 统一网络重试、请求节流、日志回调。
  - HTTP 客户端支持代理路由（HttpClient.findProxy）。
  - 日历来源: bgmlist.com/archive/<year>q<quarter>（HTML 解析）。
  - 半年番补充: bgmlist.com/api/v1/bangumi/onair（JSON API）。
  - 进度来源: Bangumi API。
  - isSubjectStillAiring(): 通过 Bangumi API 分集进度判断番剧是否在播。使用 _waitForRequestSlot 节流。
  - searchSubjects(): POST /v0/search/subjects，支持关键词搜索 + type/air_date/rating/rating_count/meta_tags 过滤 + sort排序 + limit/offset分页。
  - fetchSubjectFromApi(): GET /v0/subjects/{id} 获取完整条目 JSON。
  - fetchImageWithRetry(): 走代理的图片下载（用于封面缓存）。
  - extractBangumiIdFromBgmListItem(): 公开方法，从 BGMLIST OnAir JSON 条目中提取 Bangumi ID。

- ClashManager（lib/clash_manager.dart）:
  - 管理 mihomo 进程生命周期。
  - 启动时从 Flutter assets 提取二进制到工作目录。
  - 支持订阅 URL 自动生成 clash 配置（proxy-providers + url-test）。
  - 通过 Clash REST API（127.0.0.1:57737）查询当前节点名和延迟。
  - 窗口关闭时同步 kill 子进程。
  - URL 注入防护：applySubscription 校验订阅 URL 的 scheme 并拒绝非法字符。
  - 配置重写：每次 start 都重写配置（已移除旧的 _configNeedsUpdate）。
  - 错误可见性：start() 捕获错误存入 _startupError，main() 打印到 stderr，_bootstrap() 转储到调试日志。
  - HttpClient 泄漏修复：refreshNodeInfo 的 client.close() 移入 finally。

## 4. 关键业务流程

### 4.1 启动流程

main() 顺序:
1. ClashManager.instance.start() → 提取 mihomo → 生成配置 → 启动进程 → 等待就绪
2. 初始化窗口管理器
3. runApp(BangumiApp)

_bootstrap 顺序（runApp 后）:
1. 读设置 _loadSettings（应用代理配置至 BangumiService）。
2. 读手动修正 _loadProgressCorrections。
3. 读关注列表 _loadWatchlist。
4. 刷新日历 _refreshCalendarSchedule(initial: true)。
5. 刷新进度 _refreshProgressFromMainAction。

### 4.2 日历刷新

- 主数据源: bgmlist.com/archive/<year>q<quarter>（HTML 解析）。
- 补充数据源: bgmlist.com/api/v1/bangumi/onair（一年内开播 + Bangumi API 验证在播）。
- 支持本地缓存优先，必要时网络刷新。
- 每月 1 号可自动触发一次网络刷新。
- 刷新后调用 _archiveMissingWatchlistItemsAfterCalendar。
- isSubjectStillAiring 在 _checkSubjectStillAiring 层统一调用 _waitForRequestSlot() 节流。

### 4.3 日历数据流

```
BGMLIST Archive HTML  →  parseDailySchedule()  →  当季番剧
BGMLIST OnAir JSON    →  _enrichWithOnAirShows()
                           ├─ 过滤一年内开播
                           ├─ isSubjectStillAiring() 并发验证（已节流）
                           └─ 追加到周历
_convertScheduleFromJstForDisplay()  →  时区转换
_calendarCacheManager.save()        →  持久化
_applyScheduleData()                →  UI 刷新
```

### 4.4 番剧搜索流程

```
用户输入关键词 / 浏览模式
  → _performSearch(keyword)
  → _service.searchSubjects(keyword, type:2, sort, air_date, rating, rating_count, meta_tags filter)
  → 分页抓取 → 去重 → 按匹配度排序
  → 展示搜索结果（每页 10 条，支持翻页）
  → 后台缓存封面（通过 BangumiService 走代理下载）
```

搜索页支持**浏览模式**：隐藏搜索框，默认 keyword="*"（全部条目），搭配过滤器 + 排序实现榜单浏览。过滤器包括：
- 分类（TV/WEB/OVA/剧场版/动态漫画/其他，单选）
- 地区（日本/中国/韩国/美国/英国/法国/其他，单选）
- 播出年份范围
- 最低评分 + 最低评分人数
- 标签（手动输入 + 28 个常用标签快速选择）
- 排序（收藏数 / 评分）

### 4.5 条目详情弹窗流程

```
点击封面/标题
  → _showSubjectDetail(item)
  → showModalBottomSheet + DraggableScrollableSheet
  → _loadData():
      → fetchSubjectFromApi(subjectId) 获取完整 JSON
      → coverCacheManager.ensureCached() 缓存封面
      → setState() 展示数据
  → 内容: 标题、封面(右侧)、评分分布柱状图(右侧封面下方，可悬停查看详情)、
          信息徽章、类型标签、制作信息、简介(可展开+复制)、
          关注按钮、在浏览器中打开
```

评分分布柱状图采用 Row + Container 小方块渲染（非 CustomPaint），底部无数字标注，鼠标悬停显示 "X分, XX人" 浮层。

### 4.6 代理设置

设置面板包含:
- Clash 状态行：当前节点名 + 延迟 + 重启按钮
- Clash 订阅链接输入框
- 启用代理开关（默认开启，127.0.0.1:7890）

代理应用流程:
1. 用户输入订阅 URL → 保存
2. `applySubscription()` 生成含 `proxy-providers` 的 clash 配置（校验 URL scheme）
3. Clash 重启 → 通过 `url-test` 以 `api.bgm.tv` 为目标测速选优
4. `health-check` 每 5 分钟检测节点可用性
5. 所有 HTTP 请求走 `HttpClient.findProxy` → 127.0.0.1:7890

### 4.7 封面加载机制

- Image.network 不走 Clash 代理 → lain.bgm.tv 直连超时。
- 解决方案：通过 BangumiService.fetchImageWithRetry（走代理）下载 → CoverCacheManager.ensureCached 存本地 → Image.file 显示。
- 搜索 Tab: _cacheSearchResultCovers() 串行下载，每张完成即 setState 实时刷出。
- 其他 Tab: applyRealtimeUpdate() 在封面缓存完成后触发重建。
- applyRealtimeUpdate 使用 _allItemsIndex / _todayItemsIndex / _watchlistIndex / _scheduleDataIndex 四个 Map 索引实现 O(1) 查找替换。
- 修改列表的 setState 必须同时调用 _rebuildAllIndices() 同步索引。

### 4.8 AppBar 远程背景图

- 支持 http/https URL 作为 AppBar/TabBar 背景图。
- 通过 AppBarRemoteImage widget（lib/widgets/app_bar_remote_image.dart）渲染。
- 内部使用独立 HttpClient 直连（不走 Clash 代理），带 8s 超时，超时/失败回退到纯色 fallback。

### 4.9 关注页排序

- 追番/补番统一使用 _watchlistLastUpdated 时间戳降序排列。
- 时间戳在进度刷新、补番前进/后退时更新。
- 补番操作的排序更新延迟生效（_sortFrozen 冻结机制），下次 build 触发时刷新顺序。
- 时间戳持久化到 app_state.json（watchlist_last_updated_v1 字段）。

### 4.10 补番条目进度

- 补番条目不再跳过进度刷新。
- 走轻量路径：仅调 fetchSubjectFromApi 获取评分 + 总集数，不拉分集列表 / 评论热度 / 放送时刻。
- 结果存入 _progressCache，可在补番 Tab 的评分徽章中显示。

## 5. 持久化结构约定

### 5.1 app_state.json

app_settings_v1 字段（完整）:
- progress_concurrency: int, 1..30
- cover_cache_concurrency: int, 1..24
- api_user_agent: String
- theme_mode_v1: system/light/dark
- appbar_background_image_enabled: bool
- appbar_background_image_path: String
- timezone_conversion_enabled: bool
- timezone_offset_minutes: int, -720..840
- proxy_enabled: bool（默认 true）
- proxy_host: String（默认 127.0.0.1）
- proxy_port: int（默认 7890）
- proxy_bypass: String
- proxy_subscription_url: String（Clash 订阅链接）

其他持久化字段:
- progress_corrections_v1 / progress_correction_deltas_v1 / correction_base_v1: 手动进度修正
- catch_up_progress_v1 / catch_up_total_eps_v1 / catch_up_titles_v1: 补番进度
- watchlist_last_updated_v1: 关注列表排序时间戳
- watchlist: 关注列表
- calendar_auto_refresh_month / calendar_cache_timezone_token_v1: 日历缓存控制

### 5.2 watch_archive.json / calendar_cache.json

无变化。

## 6. 重要约定与不变量

1. 所有业务数据持久化在 Directory.current（exe 所在目录）。
2. API UA 与页面抓取 UA 分离。
3. 进度来源优先 Bangumi API。
4. 修改关注/周历逻辑时保证 _scheduleData 与缓存回填一致。
5. mihomo.exe 在首次运行时从 Flutter assets 提取到工作目录。
6. 窗口关闭时同步调用 ClashManager.kill() 终止 mihomo 进程，不等待。
7. 封面通过代理下载到本地后以 Image.file 显示，不使用 Image.network。AppBar 背景图除外（直连 + 8s 超时）。
8. **新功能隔离**：新功能（除非涉及核心状态/业务逻辑的深度改动）优先在 `lib/widgets/` 或 `lib/services/` 中实现，避免扩充 `lib/main.dart`。
9. **索引同步**：修改 _allItems / _todayItems / _watchlist / _scheduleData 的 setState 必须同时调用 _rebuildAllIndices()。
10. **Clash 配置重写**：applySubscription 每次 start 都重写配置，写入前校验 URL scheme 和非法字符。
11. **补番排序冻结**：补番操作的排序更新在当前会话中延迟生效（_sortFrozen 标志）。

## 7. 调试能力

- 日志窗口（网络/状态日志）
- 调试今日星期
- 调试归档
- Clash 启动异常可见（调试日志第一条显示"代理: 启动阶段异常: ..."）

## 8. 近期改动焦点

- **搜索页浏览模式**：新增浏览/搜索模式切换，浏览模式隐藏搜索框，自动 keyword="*" 展示全部条目，叠加过滤器 + 排序实现榜单浏览。
- **过滤器扩充**：分类（TV/WEB/OVA/剧场版/动态漫画/其他）、地区（日本/中国/韩国等）、评分人数门槛、标签快速选择（28 个常用标签）。
- **补番评分支持**：补番条目在进度刷新时仅抓取评分 + 总集数，不拉分集数据。
- **ClashManager 安全加固**：URL 注入防护、HttpClient 泄漏修复、配置重写精确化、启动错误可见化。
- **OnAir 节流**：_checkSubjectStillAiring 统一调用 _waitForRequestSlot()。
- **封面缓存 O(n²)→O(1)**：新增 _rebuildAllIndices() 和四个 Map 索引。
- **代码清理**：重复日志删除、去重函数抽取（_parseUpdateTimeMinutes / _sortResults）、CoverCacheManager 死分支清理。
- **bangumi-id 提取复用**：_extractBangumiIdFromBgmListItem 公开化。
- **评分分布柱状图重构**：CustomPaint → Row+Container，删除底部标注，添加悬停浮层（X分, XX人）。
- **分集评论柱状图强化**：悬停浮层增加集数显示（第X集, 评论XXX）。
- **关注页排序重构**：统一时间戳排序，补番排序延迟生效，时间戳持久化。
- **AppBar 远程背景图超时**：新增 AppBarRemoteImage widget，直连 + 8s 超时。

## 9. 后续改动清单

1. 修改持久化字段时，同时更新读取默认值和写回逻辑。
2. 修改代理/Clash 逻辑时，检查 ClashManager 与 BangumiService 的协调。
3. 修改周历来源时，检查 _enrichWithOnAirShows 与 parseDailySchedule 的一致性。
4. 修改网络头时，确认 API 与页面抓取 UA 的隔离未被破坏。
5. 提交前至少执行 flutter analyze 与目标测试。
6. 修改搜索相关逻辑时，注意 BangumiService.searchSubjects 的 sort/filter 参数。
7. 修改 _allItems/_todayItems/_watchlist/_scheduleData 时别忘了同步 _rebuildAllIndices()。

## 10. 新会话接力模板

请先阅读项目根目录的 PROJECT_HANDOFF.md，然后在不改变既有约定的前提下继续开发。
必须遵守:
1. 业务数据持久化保持在 exe 所在目录（Directory.current）。
2. API UA 可配置，但页面抓取与图片请求继续使用固定 browserUserAgent。
3. 手动修正进度逻辑不得回退。
4. 修改代理/Clash 逻辑时保证 ClashManager 生命周期与 app 一致。
5. 窗口关闭时必须同步终止 mihomo 进程（ClashManager.kill()）。
6. 修改 _allItems 等列表后必须同步调用 _rebuildAllIndices()。

## 11. Release 构建

- 运行 `powershell -File build_release.ps1` 自动完成构建 + 打包 ZIP。
- 输出: `release\cyberbangumi_pro-v{version}-windows-x64.zip`。
- 构建过程中自动清理运行时文件（app_state.json 等），首次启动以默认值运行。
