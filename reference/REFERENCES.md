# 参考项目分析文档

> 2026-05-30  |  时光镜 TimeLens 设计参考

---

## 1. aw-webui (ActivityWatch 官方 Web 前端)

**技术栈**: Vue 3 + TypeScript + d3 + chart.js  
**路径**: `activitywatch/aw-server/aw-webui/`  
**Stars**: 官方项目，随 ActivityWatch 主仓库发布

### 1.1 查询模式 (queries.ts)

这是最有参考价值的文件。定义了 aw-query 的标准模式：

```typescript
// 核心查询流程
canonicalEvents() {
  1. flood(query_bucket(bid_window))      // 获取窗口事件
  2. filter_period_intersect(events, AFK) // 过滤 AFK 时段
  3. categorize(events, categories)        // 按规则分类
  4. filter_keyvals(events, category)     // 按分类筛选
}

// 应用聚合查询 — 直接可用于我们的 Dashboard
appQuery() {
  events = canonicalEvents(params)
  title_events = merge_events_by_keys(events, ["app", "title"])
  app_events   = merge_events_by_keys(title_events, ["app"])    // ← 我们的饼图数据源
  cat_events   = merge_events_by_keys(events, ["$category"])
  duration = sum_durations(events)
  
  RETURN = {app_events, title_events, cat_events, duration}
}

// Android 特殊处理
// Android 没有 AFK bucket，查询简化
// Android 事件量更大，用 merge_events_by_keys 先做去重
activityQueryAndroid() {
  events = query_bucket(androidbucket)
  RETURN = sum_durations(events)
}
```

**TimeLens 复用**：我们的 `AWClient.query()` 直接套用 `appQuery()` 的 query 语句，只需替换 bucket ID 和时间范围参数。

### 1.2 可视化组件

**Summary 组件** (`visualizations/summary.ts`) — 水平条形图：

```
实现方式: 纯 SVG + d3 (无重图表库)
特点:
├── 相对宽度: barWidth = (app.duration / maxDuration) * 100%
├── 颜色策略: 每应用独立颜色 (基于 app name hash)
├── 交互: hover 变暗 + tooltip 显示精确时长
├── 链接: 点击可跳转到 app 详情
└── 性能: 零依赖，10+ 年稳定

流程:
  1. d3.select(container).append('svg')
  2. 遍历 apps: apppend('rect') + append('text')
  3. hover: rect.style('fill', darkerColor)
```

**SelectableVisualization** — 可视化切换架构：

```
支持的可视化类型:
├── top_apps          → aw-summary (水平条)
├── timeline_barchart → chart.js 柱状图
├── sunburst_clock    → d3 sunburst
├── category_tree     → 树状图
├── vis_timeline      → vis-timeline
└── score             → 评分视图

每个类型有 available 状态检查:
  available: this.activityStore.window.available
  // 没有对应数据源时隐藏选项
```

**TimeLens 复用**：
- Phase 1 饼图可用 fl_chart（比纯 SVG 简单）
- 水平条形图直接用 Flutter Row + Container（比 d3 更简单）
- available 状态检查模式：检查 aw-server 是否运行、是否有窗口数据

### 1.3 分类系统

```typescript
// 浏览器识别
browser_appname_regex: {
  chrome:  '(?i)^(google[-_ ]?chrome|chrome|chromium)',
  firefox: '(?i)(firefox|librewolf|waterfox|nightly)',
  edge:    '(?i)^(microsoft[-_ ]?edge|msedge)',
  // ... 14 种浏览器覆盖
}

// 分类规则
categorize(events, [[["Productive"], {type: "regex", regex: "..."}], ...])
```

**TimeLens 复用**：Phase 3+ 可加入应用分类，现在不需要。

---

## 2. Produktive (社区 QML 前端)

**技术栈**: Qt 5.15 + QML + Kirigami + QtCharts  
**作者**: NicoWeio  
**Stars**: 5  
**备注**: 基于 ActivityWatch 官方的 UI mockup 实现

### 2.1 Dashboard 设计 (Dashboard.qml)

```
布局: 三栏响应式
├── 左: 饼图 (QtCharts PieSeries)
│   └── 按 productive/distracting/uncategorized 三类着色
├── 中: 今日总时长 + 设备分布
│   ├── "5h 41m today"
│   └── 设备图标 + 各设备时长 (电脑/手机/TV)
└── 右: Top Applications 列表

图表: QtCharts.ChartView + PieSeries
  PieSeries {
    holeSize: 0.5              // 甜甜圈风格 (内径 50%)
    PieSlice { label: "productive"; color: categoryColor }
    // 三类: productive / distracting / uncategorized
  }
```

### 2.2 计时器组件 (KountdownDelegate.qml)

```
KountdownDelegate — 列表项计时器:
├── 图标 (Kirigami.Icon)
├── 应用名 (Kirigami.Heading)
├── 描述 (Label)
└── 时长 (Label, 右对齐)

本质上是一个带时长显示的应用列表项，不是浮窗。
```

### 2.3 多设备展示

```
设备模型:
├── computer    → 2h 18m
├── smartphone  → 2h 13m
└── tv          → 50m

每个设备显示图标 + 时长，一行排列。
```

**TimeLens 复用**：
- 饼图用甜甜圈风格 (holeSize=0.5)，视觉上比实心饼图更现代
- 分类着色思路 (productive/distracting) 可以作为后续功能
- 多设备展示模式 Phase 4 可参考

---

## 3. aw-tauri (官方在研桌面前端)

**技术栈**: Tauri (Rust) + Vue 3  
**路径**: `activitywatch/aw-tauri/`  
**状态**: 开发中

```
架构:
├── Tauri Shell (Rust) — 系统托盘、原生窗口
├── aw-webui (子模块) — 复用 Web 前端代码
└── aw-notify (子模块) — 通知模块

特点:
├── 复用 aw-webui 的全部 UI 代码
├── Tauri 比 Electron 轻量 (~5MB vs ~200MB)
└── 系统托盘驻留
```

**TimeLens 参考**：
- 系统托盘 → 我们的 Mini 模式可以替代
- Tauri 的轻量思路 → 验证了"不用 Electron"是正确的
- 但 Tauri 用 Web 做 UI → 不如 Flutter 原生性能

---

## 4. 技术选型验证总结

| 对比项 | aw-webui | Produktive | TimeLens |
|--------|----------|------------|----------|
| UI 框架 | Vue 3 (Web) | QML (Qt) | Flutter (原生) |
| 图表 | d3 + chart.js | QtCharts | fl_chart |
| 饼图 | Sunburst (d3) | PieSeries (Qt) | PieChart (fl_chart) |
| 柱状图 | Timeline (chart.js) | — | BarChart (fl_chart) |
| 悬浮窗 | ❌ 无 | ❌ 无 | ✅ 核心功能 |
| 阈值提醒 | ❌ 无 | ❌ 无 | ✅ 绿/黄/红 |
| 多设备 | 支持 (query) | 静态展示 | Phase 4 |
| 桌面端 | 浏览器 | 原生 Qt | 原生 Flutter |

**核心结论**：
1. aw-webui 的 `queries.ts` 是 aw-query 语法的权威参考，直接套用
2. 图表用 fl_chart 足够 — aw-webui 自己也是 d3+chart.js 混用
3. 饼图用甜甜圈风格 (holeSize=0.5) 比实心圆更现代 — Produktive 的实践
4. 悬浮窗和阈值是我们独有的差异化 — 两个参考项目都没有

---

## 5. 避坑清单

从 aw-webui 代码中学到的已知问题和注意事项：

### 5.1 Bucket ID 匹配

```typescript
// ⚠️ 问题: find_bucket 可能匹配到错误的 bucket
// 解决: 已知完整 bucket ID 时优先用 query_bucket 直接查询
// 参考: https://github.com/ActivityWatch/aw-webui/issues/590

function queryBucket(bid: string): string {
  if (bid.endsWith('_')) {
    return `query_bucket(find_bucket("${bid}"))`;  // 模糊匹配
  }
  return `query_bucket("${bid}")`;  // 精确匹配（推荐）
}
```

**TimeLens 注意事项**: 始终用精确 bucket ID，不要用 `find_bucket`。

### 5.2 时间戳时区

```
Event 时间戳强制 UTC:
  json_data["timestamp"] = self.timestamp.astimezone(timezone.utc).isoformat();
  
→ 查询时传的 start/end 参数需用 ISO 8601 + 时区:
  "2026-05-30T00:00:00+08:00"
```

### 5.3 AFK 过滤仅桌面端

```
Android 没有 AFK bucket → activityQueryAndroid 直接返回 sum_durations
桌面端 AFK 过滤: filter_period_intersect(events, not_afk)
```

### 5.4 Android 事件去重

```
Android UsageEvents 可能产生大量事件
→ 查询前先 merge_events_by_keys(events, ["app"]) 去重
→ 否则 query API 可能超时
```

### 5.5 query API 不支持 GET

```
aw-query 只接受 POST，参数在 body 中
GET /api/0/query/ 返回空
→ 错误: 用 GET 请求 query 端点
```

### 5.6 非 AFK 时段的浏览器音频

```
如果用户在听 YouTube 但浏览器不在前台:
  filter_afk 会错误过滤掉这段时间
解决: 检测浏览器 audible 标签 + always_active_pattern
→ Phase 1 不做，但要知道这个坑
```
