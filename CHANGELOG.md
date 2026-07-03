# Changelog

## v0.7.0 (2026-07-03)

### ✨ 新增
- **搜索页浏览模式**：切换至浏览模式后隐藏搜索框，自动以 `keyword="*"` 展示全部条目，配合过滤器实现榜单浏览
- **多维过滤器**：
  - 分类：TV / WEB / OVA / 剧场版 / 动态漫画 / 其他
  - 地区：日本 / 中国 / 韩国 / 美国 / 英国 / 法国 / 其他
  - 播出年份范围（起止年份）
  - 最低评分 + 最低评分人数组合过滤
  - 标签：支持手动输入 + 28 个常用标签快速选择（ChoiceChip）
- **排序选择**：浏览模式下支持按收藏数 / 评分排序
- **补番评分**：补番条目在进度刷新时不再完全跳过，轻量抓取评分和总集数
- **补番排序冻结**：点击前进/后退时列表不立即跳动，下次进入页面时刷新顺序
- **AppBar 远程背景图超时保护**：新增 `AppBarRemoteImage` widget，8 秒超时回退

### 🔒 安全加固 (ClashManager)
- URL 注入防护：订阅 URL 写入 config 前校验 scheme 和非法字符
- HttpClient 泄漏修复：`refreshNodeInfo` 的 `client.close()` 移入 `finally`
- 配置重写精确化：移除 `_configNeedsUpdate` 子串匹配，每次 `start` 都重写
- 启动错误可见化：`_startupError` 缓冲 + stderr 输出 + 调试日志转储

### ⚡ 性能优化
- **封面缓存 O(n²)→O(1)**：新增 `_rebuildAllIndices()` 和四个 Map 索引，`applyRealtimeUpdate` 不再全量重建
- **OnAir 节流**：`_checkSubjectStillAiring` 统一调用 `_waitForRequestSlot()`，避免触发 Bangumi 429

### 🧹 代码清理
- 重复日志删除
- `_parseUpdateTimeMinutes` 抽取到 `constants.dart`（today_tab / week_calendar_tab 去重）
- `search_tab.dart` 排序逻辑抽取为 `_sortResults` 方法
- `CoverCacheManager.getCachedPath` 移除恒为 false 的死分支
- 删除 `lib/main.dart.backup`（217KB 残留文件）

### 🎨 UI 改进
- **评分分布柱状图重构**：从 `CustomPaint` 迁移到 `Row`+`Container` 渲染，删除底部数字标注，鼠标悬停显示 `X分, XX人` 浮层
- **分集评论柱状图强化**：悬停浮层增加集号显示（`第X集, 评论XXX`）
- **过滤器栏**：分类 / 地区 / 年份 / 评分 / 标签水平排列，浏览/搜索模式切换内置在栏内
- **评分弹窗**：最低评分 + 评分人数门槛合并在一个弹窗内，ChoiceChip 选择

### 🐛 Bug 修复
- `_configNeedsUpdate` 子串匹配导致订阅 URL 改短后不生效
- `refreshNodeInfo` 异常路径 HttpClient 不释放
- `_cacheAllCalendarCovers` 中相同日志追加两次
- Windows `_openUrlBySystemCommand` URL 未加引号导致空格被 `start` 误解析

---

## v0.6.1 (2026-07-02)

- 修正 PROJECT_HANDOFF 版本号
- 安全性、性能优化、关注页排序重构

## v0.6.0 (2026-07-02)

- 代码重构与优化（拆分分层架构）
- 番剧搜索 Tab
- 条目详情弹窗
- 封面加载重构
- API 文档新增（docs/v0.yaml）
