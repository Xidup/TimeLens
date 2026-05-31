# 时光镜 TimeLens — 架构设计文档

> 版本 0.0.8  |  2026-05-31  |  状态：Phase 1 进行中 (9/11)

---

## 1. 项目背景

### 1.1 问题

现代人的屏幕时间越来越长，但大多数人对自己"时间花在哪"只有模糊的感觉。市面上有 RescueTime、Screen Time 等方案，但要么收费昂贵，要么数据不在自己手里，要么功能臃肿。

### 1.2 机遇

[ActivityWatch](https://github.com/ActivityWatch/activitywatch) 是一个开源的时间追踪项目（GitHub 17.7k ⭐），提供：

- **桌面端**：`aw-server` / `aw-server-rust` — REST API 服务器，`aw-watcher-window` — 追踪当前焦点窗口
- **Android 端**：`aw-android` — 在手机上内嵌 `aw-server-rust`，通过 Android `UsageStatsManager` API 追踪应用使用
- **同步模块**：`aw-sync` — 基于文件夹的多设备数据同步（push/pull/syncBoth）

ActivityWatch 解决了"数据采集 + 存储"问题，但它的默认 UI（WebUI）体验一般，且缺少**实时可见的屏幕时间提醒**。

### 1.3 定位

时光镜 = **ActivityWatch 作为数据引擎 + 全新原生 UI + 悬浮窗实时提醒**

不做另一个全栈时间追踪工具，而是在 ActivityWatch 的肩膀上，做好"看得见的时间管理"。

---

## 2. 需求定义

### 2.1 核心需求（v0.1 必须实现）

| ID | 需求 | 描述 |
|----|------|------|
| R1 | **mm:ss 悬浮计时窗** | 前台显示当前应用今日累计使用时长，格式 `MM:SS` |
| R2 | **绿/红阈值切换** | 累计 < 30 分钟绿色背景，≥ 30 分钟红色背景 |
| R3 | **今日应用排行** | Dashboard 面板展示各应用今日使用时长排行 |
| R4 | **对接 ActivityWatch** | 通过 REST API (`localhost:5600`) 读取窗口/应用事件数据 |
| R5 | **跨平台支持** | Windows 桌面端 + Android 移动端 |

### 2.2 扩展需求（后续版本）

| ID | 需求 | 描述 |
|----|------|------|
| R6 | 多设备数据同步 | Windows ↔ Android 通过 aw-sync 共享文件夹同步 |
| R7 | 历史数据查询 | 按日/周/月查看屏幕时间趋势 |
| R8 | 定时提醒 | 达到设定时长后推送通知 |
| R9 | 应用白名单 | 某些应用不计入屏幕时间 |

### 2.3 非功能性需求

- **隐私优先**：所有数据存储在本地，同步仅通过用户控制的文件夹
- **低资源占用**：Android 端内存 < 100MB，后台 CPU 接近零
- **离线可用**：两端均可在无网络环境下独立工作
- **电池友好**：Android 端使用 AlarmManager 非精准定时，每小时最多唤醒一次

### 2.4 悬浮窗性能分析

悬浮窗通过轮询本地 `localhost:5600` API 获取当前应用使用时长。

| 轮询间隔 | 请求/小时 | 数据量/小时 (gzip) | CPU 唤醒 | 适用场景 |
|---------|-----------|-------------------|----------|---------|
| 3 秒 | 1200 | ~10.5 MB | 频繁 | Windows 桌面端（推荐） |
| 5 秒 | 720 | ~6.3 MB | 适中 | Android（平衡） |
| 10 秒 | 360 | ~3.2 MB | 较少 | 省电模式 |
| 动态 | 智能调整 | — | 最优 | 根据 app 切换频率自适应 |

**关键结论**：所有流量都是 `localhost` 环回，不走网卡，不消耗移动数据。Windows 端 3 秒间隔零负担；Android 端建议 5-10 秒或动态间隔以减少 CPU 唤醒。内存占用约 1-2KB（仅存应用名→Duration 的 Map）。

**Win32 原生悬浮窗（可选方案）**：独立的 C++ 程序，约 100KB 编译产物，WinHTTP + GDI 渲染，CPU 占用接近零。适合不想启动完整 Flutter 应用的场景。

---

## 3. 设计思路

### 3.1 核心原则

**不重复造轮子，站在 ActivityWatch 的肩膀上。**

ActivityWatch 已经解决了数据采集链路上最困难的问题：
- Android `UsageStatsManager` 权限申请与事件解析
- `ACTIVITY_RESUMED` / `ACTIVITY_PAUSED` 事件的乱序处理
- 心跳事件的去重与 duration 合并
- 多设备同步文件夹协议（aw-sync）

时光镜的增量价值在于**"让人看得见时间"** —— 一个好用的原生 UI + 一个始终可见的悬浮计时窗。

### 3.2 关键决策记录

#### 决策 1：复用 aw-android 而非自建数据采集

**选择**：复用 aw-android 的 `RustInterface`（内嵌 aw-server-rust）和 `UsageStatsWatcher`（数据采集）。

**理由**：
- aw-android 已解决 UsageStats 权限、事件乱序、心跳去重等 5+ 个边缘 case
- 自建需要 2~3 周额外开发 + 持续维护 8 个而非 3 个模块
- 额外 20MB APK + 30MB 内存换取已验证的数据引擎（2026 年手机上可忽略）
- 两端的 REST API 完全一致（都是 `localhost:5600/api/0/`），数据层代码可复用

#### 决策 2：对称架构（两端各自拥有完整服务器 + UI 客户端）

**选择**：Android 和 Windows 采用镜像架构，各有本地 aw-server-rust + 各自的 TimeLens 客户端。

**理由**：
- 两端离线可用，不依赖网络
- UI 代码的核心数据层可复用（对接同一套 REST API）
- 调试时每层有明确 API 边界，可独立验证
- 后续通过 aw-sync 的共享文件夹实现数据互通

#### 决策 3：先 Windows 后 Android，逐步交付

**选择**：v0.1 优先完成 Windows 端（Fluent UI + 悬浮窗），Android 端后续迭代。

**理由**：
- Windows 端开发环境更简单，调试更方便
- ActivityWatch 桌面端的窗口追踪数据最准确
- 悬浮窗在桌面端更实用（多窗口工作场景）
- Android 端可以复用 Windows 端已打磨的数据层代码

#### 决策 4：P2P 对等同步 — 双方都是"主设备"

**选择**：采用 P2P 对等架构，Windows 和 Android 都是完整的主设备，各自运行 aw-server-rust + aw-sync。同步后两端都能查询到全部数据。

**理由**：
- 不与某一台设备强绑定，哪台开着都能独立工作
- aw-sync 的 `syncBoth()` 天然支持双向同步
- 同步文件夹中的 `{device_id}/database.db` 文件能自然区分来源

**同步文件夹传输方案对比**：

| 方案 | 自动同步 | LAN 可用 | 互联网可用 | 跨平台 | 国内可用 | 用户设置难度 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| **Syncthing (局域网)** | ✅ | ✅ P2P | ❌ | ✅ | ✅ 不受限 | 中等 |
| Syncthing (公网中继) | ✅ | ✅ | ⚠️ 中继可能被墙 | ✅ | ❌ 不稳定 | 高 |
| 局域网 HTTP 直连 | ⚠️ 自己实现 | ✅ | ❌ | ✅ | ✅ | 高(开发) |
| 手动导入/导出 | ❌ | ✅ | ✅ | ✅ | ✅ | 高 |

**推荐方案：Syncthing 局域网模式**

```
┌─────────────┐   Syncthing (同一WiFi)    ┌─────────────┐
│   Windows   │◄─────────────────────────►│   Android   │
│             │      192.168.x.x          │             │
│ aw-server   │                           │ aw-server   │
│   └─aw-sync │    同步文件夹               │   └─aw-sync │
│     syncBoth│  ~/TimeLensSync/          │     syncBoth│
└─────────────┘                           └─────────────┘

关键设计决策：
• 默认只走局域网，不依赖公网中继
• 出家门 → 各自独立记录 → 回家自动追同步
• 避免国内运营商 NAT 穿透问题
• Syncthing 国内社区有镜像源可用
```

**自动同步 vs 手动同步**：
- Phase 1/2：手动触发"同步"按钮，执行 aw-sync syncBoth
- Phase 3+：可选后台同步（仅局域网内，WiFi 连接时自动触发）
- **后台自动同步非必须**：个人用户 2-3 台设备，每天打开应用时手动同步一次即可

#### 决策 5：Android 平板适配策略

**选择**：通过 Flutter Responsive Layout 适配大屏，不额外维护独立的平板 UI。

**理由**：
- Flutter 的 `LayoutBuilder` + `Breakpoint` 可自动根据屏幕宽度切换布局
- 平板端 Dashboard 使用双栏布局（左侧应用列表 + 右侧详情/图表）
- 悬浮窗在平板端可调整为更大的尺寸和字号
- 与手机端共享同一套 Dart 代码，零额外维护成本

**平板端特殊处理**：
- Dashboard: 750dp 以上切换为 Master-Detail 双栏布局
- 悬浮窗: 字体和 padding 等比放大
- 通知: 利用大屏空间显示更丰富的内容

#### 决策 6：通知策略

**选择**：采用**阈值触发式通知**为主，**每日汇总**为辅。

| 通知类型 | 触发条件 | 示例 | 优先级 |
|---------|---------|------|:---:|
| 单应用阈值 | 任一应用单设备累计 ≥ 60 分钟 | "Chrome 已使用 1 小时，该休息了" | 高 |
| 单设备阈值 | 单设备总屏幕时间 ≥ 设定值 | "今天已经看手机 3 小时了" | 中 |
| 多设备汇总 | 所有设备总屏幕时间 ≥ 设定值 | "今日全设备屏幕时间已达 6 小时" | 低 |
| 每日定时 | 每天固定时间推送今日摘要 | "今日屏幕时间报告：总计 5h23m" | 低 |

**单设备 vs 多设备汇总**：
- 默认以**单设备时长**为准，因为"你已经在手机上刷了 1 小时"比"你在所有设备上总共用了 1 小时"更有行为指导意义
- 多设备总时长作为可选的"全局健康指标"，用户可自行设置阈值
- 悬浮窗的绿/红阈值始终是单设备维度（避免跨设备时长的歧义）

#### 决策 8：悬浮窗交互设计（Windows 端简化）

**选择**：Windows 桌面端悬浮窗锁定在屏幕角落，零交互。通过系统托盘菜单管理。

**交互行为**：

| 操作 | 行为 | 说明 |
|------|------|------|
| 悬浮窗本体 | 无任何交互 | 不响应双击/拖动/长按/右键 |
| 系统托盘菜单 | 打开面板 / 切悬浮窗 | 主入口 |
| 系统托盘菜单 | 四角位置切换 | 默认左下角 |
| 系统托盘菜单 | 退出应用 | 关闭托盘 + 进程 |

**Windows 端简化理由**：
- 桌面端无手指误触风险，不需要锁定/解锁切换
- 鼠标操作准确，点击只占极少面积，不会误触
- 角落定位的悬浮窗本身就是被动显示（FPS 计数器模型）
- Android 端保留原有完整交互设计（手指操作场景不同）

**颜色规则 — 每应用可配置阈值**：

```dart
// 默认规则：所有应用适用
DefaultColorRule:
  0 ~ 30 分钟     → #2E7D32 绿色
  30 ~ 60 分钟    → #F9A825 黄色
  > 60 分钟       → #C62828 红色

// 每应用覆盖规则（用户可配）
PerAppColorRule:
  Feishu (飞书):  0~180min 绿 → >180min 红   (工作应用放宽)
  Douyin (抖音):  0~30min 绿 → >30min 红     (娱乐应用收紧)
  WeChat (微信):  0~60min 绿 → 60~120min 黄 → >120min 红
```

**数据模型**：
```dart
class AppThresholdConfig {
  String appPattern;     // "Feishu" 或 "*" (匹配所有)
  List<ThresholdStep> steps;  // 多级阈值
}

class ThresholdStep {
  Duration maxDuration;  // 此步上限
  Color backgroundColor; // 背景色
  Color textColor;       // 文字色 (默认白色)
}
```

**配置界面**：Dashboard 设置页 → "应用规则" → 从今日应用列表中选择 → 设定阈值和颜色。

**视觉风格**：

| 元素 | 规格 |
|------|------|
| 样式 | FPS 计数器风格，边角定位 |
| 背景 | `rgba(0,0,0,0.4)` 半透明黑，圆角 6px |
| 应用名 | 小字，白色 70% 透明度 |
| 计时数字 | 大字，等宽字体 (Consolas/ monospace)，字间距 2px |
| 阈值颜色 | 仅改变文字颜色：`<30min` 绿 `#66BB6A` → `30-60min` 黄 `#F9A825` → `>60min` 红 `#EF5350` |
| 背景色 | 始终不变（不用大块背景色体现实色阈值） |
| 桌面时 | 隐藏悬浮窗（aw-watcher-window 报告 explorer.exe 或无焦点窗口时） |

#### 决策 7：事件驱动式计时

**选择**：前端本地 Timer 负责 UI 体验（每秒流动），系统数据负责权威记录。切换时丢弃 Timer 取系统数据，不校准。

**平台差异**：

| 操作 | Windows | Android |
|------|---------|---------|
| 数据源 | aw-server API (信任 aw-watcher-window) | 系统 UsageStats |
| 检测频率 | 5 秒轮询 API 最新事件 | 5 秒检测前台 app |
| 切换时 | 读 API 获取新 app 时长 → 重置 Timer | 读系统数据获取新 app 时长 → 重置 Timer |
| 同 app 持续时 | 本地 Timer 逐秒自增 | 本地 Timer 逐秒自增 |

**实现逻辑**：
```
1. 初始: 读数据源获取当前 app + 今日已有时长 → 启动本地 Timer
2. 每 5 秒检测:
   ├── 同一 app   → Timer 继续跑，不访问数据源
   ├── 桌面/锁屏   → 隐藏悬浮窗，暂停 Timer
   └── 切换其他app → 丢弃当前 Timer → 读数据源取新值 → 重启 Timer
3. 不做校准，Timer 的几秒误差可忽略
```

**理由**：悬浮窗是即时视觉提示，不是精确记录工具。几秒误差不影响体验，校准带来的复杂度远大于收益。

#### 决策 9：Dashboard 可视化图表

**选择**：使用 `fl_chart`（MIT 协议）实现三类核心图表。

**图表清单**：

| 图表 | 位置 | 数据源 | 说明 |
|------|------|--------|------|
| **今日饼图** | Dashboard 顶部 | 今日 events 按 app 聚合 | 直观展示各 app 时间占比 |
| **趋势柱状图** | Dashboard 中部 | 近 7 天每日总时长 | 横向对比，发现趋势 |
| **应用详情折线图** | 点击应用进入 | 该 app 近 7 天每日时长 | 单个应用的深度分析 |

**饼图交互**：
- 点击扇区 → 高亮 + 显示精确时长
- 占比 <5% 的应用合并为"其他"

**柱状图/折线图**：
- X 轴：日期（近 7 天）
- Y 轴：时长（分钟）

**技术选型**：
- `fl_chart`：MIT 协议，轻量，支持 PieChart / BarChart / LineChart
- Phase 1 仅单设备展示，多设备图表与家庭管理并列 Phase 4

---

## 4. 技术路线

### 4.1 技术栈

| 层 | Windows | Android | 说明 |
|----|---------|---------|------|
| **数据引擎** | aw-server-rust | aw-server-rust (JNI) | ActivityWatch 官方 Rust 实现 |
| **数据采集** | aw-watcher-window | UsageStatsWatcher | 桌面追踪焦点窗口，手机追踪前台应用 |
| **本地存储** | SQLite | SQLite | aw-server-rust 内建 |
| **API 协议** | REST (localhost:5600) | REST (localhost:5600) | 两端接口一致 |
| **UI 框架** | Flutter (fluent_ui) | Flutter (Material Design) | 一套 Dart 代码，双端编译 |
| **状态管理** | Riverpod | Riverpod | Flutter 推荐的状态管理方案 |
| **HTTP 客户端** | Dio | Dio | Dart HTTP 库 |
| **图表** | fl_chart | fl_chart | 饼图/柱状图/折线图 (MIT) |
| **悬浮窗** | Flutter Mini 模式 / Win32 原生 | Android Overlay Service | 平台特化实现 |

### 4.2 为什么不选其他方案

| 方案 | 不选的理由 |
|------|-----------|
| WinUI 3 + Jetpack Compose 双原生 | 无法复用 UI 代码，维护成本翻倍 |
| Electron | 桌面端太重（~200MB），不适合悬浮窗 |
| React Native | 悬浮窗和原生 API 调用受限 |
| Kotlin Multiplatform | 生态不如 Flutter 成熟，UI 组件库少 |
| 纯 Web (PWA) | 无法做系统级悬浮窗，无法调用 UsageStats API |

**Flutter 在本项目中的适配性**：
- ✅ 一套代码编译 Windows + Android 原生应用
- ✅ Material Design 内建支持（Android 端）
- ✅ `fluent_ui` 包提供 Fluent Design 组件（Windows 端）
- ✅ `window_manager` 插件支持无边框置顶窗口（悬浮窗基础）
- ✅ `dio` HTTP 客户端稳定可靠
- ✅ Platform Channel 可调用原生 API（Android 悬浮窗需要）

### 4.3 编程语言分布

```
Rust    ████████░░  40%  aw-server-rust 内核，编译为 .so
Dart    ██████░░░░  30%  Flutter 跨平台 UI
Kotlin  ███░░░░░░░  15%  Android 原生层（UsageStatsWatcher、Overlay Service）
C++     ██░░░░░░░░  10%  Windows 原生悬浮窗（可选）
Python  █░░░░░░░░░   5%  构建脚本、开发工具
```

---

## 5. 项目架构

### 5.1 仓库结构

```
TimeLens/
├── ARCHITECTURE.md           # 本文件 — 架构设计文档
├── .gitignore
│
├── activitywatch/            # ActivityWatch 主仓库 (git submodule)
│   ├── aw-server-rust/       #   Rust 服务器 + aw-sync 同步模块
│   ├── aw-watcher-window/    #   桌面窗口追踪器
│   └── ...                   #   其他子模块
│
├── aw-android/               # aw-android (参考实现，不完全 fork)
│   └── mobile/src/main/java/net/activitywatch/android/
│       ├── RustInterface.kt          # JNI 桥接 → aw-server-rust .so
│       ├── UsageStatsWatcher.kt      # Android UsageStats 数据采集
│       ├── MainActivity.kt           # 应用入口
│       └── watcher/                  # 后台采集器
│
└── timelens_app/             # Flutter 跨平台前端
    ├── pubspec.yaml
    ├── lib/
    │   ├── main.dart                  # 应用入口 + 平台检测
    │   ├── core/
    │   │   ├── api_client.dart        # ActivityWatch REST API 封装
    │   │   ├── timer_service.dart     # 计时轮询 + 阈值判断
    │   │   └── window_manager.dart    # Windows 窗口模式切换
    │   ├── features/
    │   │   ├── dashboard/             # 主面板（应用排行、统计）
    │   │   ├── overlay/               # 悬浮计时窗（mm:ss）
    │   │   └── sync/                  # 数据同步界面（后续版本）
    │   └── shared/
    │       └── widgets/               # 共用 UI 组件
    ├── android/                       # Android 原生层
    │   └── app/src/main/kotlin/
    │       └── overlay/               # Overlay Service（悬浮窗）
    └── windows/                       # Windows 原生层
        └── overlay_native.cpp         # Win32 独立悬浮窗（可选）
```

### 5.2 模块职责

```
┌─────────────────────────────────────────────┐
│                时光镜 TimeLens              │
├─────────────────────────────────────────────┤
│                                              │
│  ┌──────────────────┐  ┌──────────────────┐ │
│  │   Fluent UI      │  │  Material Design  │ │
│  │   (Windows)      │  │   (Android)       │ │
│  │                  │  │                   │ │
│  │ Dashboard 悬浮窗  │  │  Dashboard 悬浮窗 │ │
│  └────────┬─────────┘  └────────┬──────────┘ │
│           │                     │            │
│  ┌────────▼─────────────────────▼──────────┐ │
│  │          数据层 (共享代码)               │ │
│  │  ┌──────────┐  ┌───────────────────┐    │ │
│  │  │AWClient  │  │  TimerService     │    │ │
│  │  │REST API  │  │  轮询+阈值+mm:ss   │    │ │
│  │  └────┬─────┘  └───────────────────┘    │ │
│  └───────┼─────────────────────────────────┘ │
│          │                                   │
│  ┌───────▼─────────────────────────────────┐ │
│  │          aw-server-rust                 │ │
│  │  ┌─────────┐ ┌────────┐ ┌───────────┐  │ │
│  │  │REST API │ │SQLite  │ │ aw-sync   │  │ │
│  │  │ :5600   │ │ 本地DB │ │ push/pull │  │ │
│  │  └─────────┘ └────────┘ └───────────┘  │ │
│  └─────────────────────────────────────────┘ │
│                                              │
└─────────────────────────────────────────────┘
```

### 5.3 数据流

```
Android 手机端数据流：

  UsageStatsManager         UsageStatsWatcher         aw-server-rust
  (Android 系统)            (Kotlin)                  (Rust JNI)
       │                        │                         │
       │  queryEvents()         │                         │
       │──────────────────────► │                         │
       │                        │                         │
       │  UsageEvents 列表       │  heartbeat(timestamp,   │
       │  (RESUMED/PAUSED)      │   duration, app_name)   │
       │                        │───────────────────────► │
       │                        │                         │
       │                        │                    ┌────▼────┐
       │                        │                    │ SQLite  │
       │                        │                    │  存储    │
       │                        │                    └────┬────┘
       │                        │                         │
       │                  TimeLens App              REST API
       │                  (Flutter/Dart)           :5600
       │                        │                      │
       │                        │  GET /api/0/buckets/ │
       │                        │  /events?limit=100   │
       │                        │─────────────────────►│
       │                        │                      │
       │                        │◄─────────────────────│
       │                        │   JSON events        │
       │                        │                      │
       │                   ┌────▼────┐                 │
       │                   │TimerService              │
       │                   │ 累计时长                  │
       │                   │ mm:ss 格式化              │
       │                   │ 绿/红阈值判断              │
       │                   └────┬────┘                 │
       │                        │                      │
       │                   ┌────▼────┐                 │
       │                   │悬浮窗UI  │                 │
       │                   │12:34    │                 │
       │                   └─────────┘                 │


同步数据流 (Phase 2+, Syncthing + aw-sync)：

  任意设备                    同步文件夹                   任意设备
  ┌──────────┐        Syncthing 自动同步          ┌──────────┐
  │ Windows  │           TimeLensSync/            │ Android  │
  │          │  ┌──────────────────────────────┐  │          │
  │ aw-sync  │  │  windows-device-id/db.db     │  │ aw-sync  │
  │          │  │  android-device-id/db.db     │  │          │
  │ syncBoth │  │  pad-device-id/db.db (平板)   │  │ syncBoth │
  │    │     │  └──────────────────────────────┘  │    │     │
  │    │     │              ▲                      │    │     │
  │    ▼     │              │                      │    ▼     │
  │ push()───┼──写入本机.db──┘                      │ push()───┼──写入本机.db
  │          │                                     │          │
  │ pull()◄──┼──读取其他.db──                       │ pull()◄──┼──读取其他.db
  │          │                                     │          │
  │ 查询：   │                                     │ 查询：   │
  │ 本机bucket                                    │ 本机bucket
  │ + synced-from-*                               │ + synced-from-*
  │ = 全量数据                                    │ = 全量数据
  └──────────┘                                     └──────────┘

  特色：
  • 每台设备都是对等节点，pull 后都能看到全量数据
  • 3+ 设备自然扩展，各自只操作自己的 device-id 子目录
  • Syncthing 负责传输，aw-sync 负责数据协议
  • 离线可用，联网时自动同步
```

---

## 6. 开发阶段

### Phase 1：Windows 端 MVP（当前）

```
目标：Windows 桌面端可运行，悬浮窗 + Dashboard 核心功能完整

具体任务：
├── Task 1.1  初始化 Flutter 项目 + 依赖配置                [✅ 已完成]
├── Task 1.2  AWClient — REST API 对接                     [✅ 已完成]
├── Task 1.3  TimerService — 事件驱动计时                    [✅ 已完成]
├── Task 1.4  Dashboard — 主面板 UI                          [✅ 已完成]
│              · 焦点恢复自动刷新 · 连接状态横幅 · 今日摘要卡片
│              · 应用排行（序号圈+三档阈值色+60min基线进度条）
│              · 四态：Loading/断开/无数据/已加载 · 过滤自身
├── Task 1.5  OverlayWindow — FPS 透明悬浮窗                 [✅ 已完成]
│              · 透明背景（可配 backgroundOpacity 接口）
│              · 仅文字颜色随阈值变化 · 圆角 6px · 去阈值指示点
├── Task 1.6  WindowManager — Mini 模式切换                 [✅ 已完成]
│              · onModeChanged 回调（联动外部组件）
│              · 幂等保护（重复调用无害）
│              · 桌面检测集成（explorer.exe → 自动暂停）
│              · Mini 模式桌面时悬浮窗自动隐藏
├── Task 1.7  main.dart — 应用入口 + 模式路由               [✅ 已完成]
│              · 平台自适应：Windows=FluentApp, 其他=MaterialApp
│              · serverRunning 联动初始 UI（消除加载闪烁）
│              · onModeChanged 实装（模式切换自动同步状态）
│              · 提取 _buildHome() 统一路由逻辑
├── Task 1.8  悬浮窗交互 (拖动/长按锁定/双击/右键菜单)         [✅ 已完成 — 决策调整]
│              · 设计决策：Windows 悬浮窗锁定、零交互
│              · 系统托盘菜单（打开面板、切换位置、退出）
│              · 四角位置可配（默认左下角）
│              · tray_manager 集成
├── Task 1.9  每应用阈值配置 (AppThresholdConfig + 设置UI)    [✅ 已完成]
│              · JSON 持久化（ThresholdStore → %APPDATA%/TimeLens/）
│              · 数据模型序列化（toJson/fromJson）
│              · Dashboard 内嵌可折叠设置面板
│              · 滑块编辑对话框（绿→黄/黄→红 双阈值）
│              · 颜色预览 + 添加/恢复默认规则
│              · TimerService.updateConfigs() 运行时更新
├── Task 1.10 Dashboard 图表 (fl_chart 饼图 + 柱状图)         [ ]
└── Task 1.11 真机调试 + 与 aw-server 联调                   [ ]
```

### Phase 2：Android 端移植 + 手动同步

```
目标：Android 手机+平板可运行，手动同步可用

具体任务：
├── Task 2.1  集成 aw-android 的 RustInterface + UsageStatsWatcher
├── Task 2.2  替换 WebUI → Material Design（复用 Phase 1 数据层代码）
├── Task 2.3  Android 悬浮窗 Overlay Service（事件驱动计时）
├── Task 2.4  后台持久化（Foreground Service + 通知栏）
├── Task 2.5  Responsive Layout — 平板双栏布局适配
├── Task 2.6  aw-sync 集成（syncBoth + 局域网 Syncthing 引导）
├── Task 2.7  同步后 Dashboard 显示远程设备数据（分设备展示）
└── Task 2.8  端到端测试 + Play Store 准备
```

### Phase 3：通知 + 增强功能

```
目标：通知系统，数据可视化增强

具体任务：
├── Task 3.1  阈值通知系统
│             ├── 单应用超时提醒
│             ├── 单设备总时长提醒
│             └── 每日定时摘要
├── Task 3.2  历史趋势图表（日/周/月，按设备可选）
├── Task 3.3  高级 Dashboard（时间线视图，合并多设备数据）
├── Task 3.4  设置页面（阈值可调、白名单、导出、同步频率）
└── Task 3.5  局域网 WiFi 连接时自动同步（可选）

### Phase 4：家庭管理（远期规划）

```
目标：多用户/家庭设备管理

具体任务：
├── Task 4.1  设备分组管理（家庭成员分组）
├── Task 4.2  家长控制模式（限制子设备使用时长）
├── Task 4.3  家庭使用报告（周报/月报）
├── Task 4.4  共享白名单（家庭公共应用不计时）
└── Task 4.5  跨互联网同步（需自建中继或国内云方案）
```

---

## 7. 附录

### A. 开源协议

| 组件 | 协议 | 对我们影响 |
|------|------|-----------|
| ActivityWatch (主仓库) | MPL 2.0 | 修改 MPL 文件需保留协议声明 |
| aw-android | MPL 2.0 | 修改 .kt 文件需保留协议声明 |
| aw-server-rust | MPL 2.0 | 编译为 .so 嵌入，无额外义务 |
| Syncthing | MPL 2.0 | 不修改，仅作为外部依赖 |
| timelens_app (Flutter) | 自选 | 新增代码，不受 MPL 约束 |

**MPL 2.0 关键条款**：
- 文件级 Copyleft：仅在修改 MPL 许可的源文件时需要公开该文件的改动
- 新增文件可以任意协议，不受 MPL 约束
- 允许商用、闭源发布、App Store 上架
- 允许与私有代码链接和打包

### B. ActivityWatch REST API 速查

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/0/info` | GET | 服务器信息（hostname, version, device_id） |
| `/api/0/buckets/` | GET | 所有数据桶列表 |
| `/api/0/buckets/{id}` | GET/POST/PUT/DELETE | 桶的 CRUD |
| `/api/0/buckets/{id}/events` | GET/POST | 获取/创建事件 |
| `/api/0/buckets/{id}/heartbeat` | POST | 心跳上报（合并同 app 事件） |
| `/api/0/query/` | POST | aw-query 复杂查询 |
| `/api/0/export` | GET | 导出所有数据 |
| `/api/0/settings` | GET/POST | 服务器设置 |

**Event 数据格式**：
```json
{
  "id": 123,
  "timestamp": "2026-05-30T14:30:00+00:00",
  "duration": 120.5,
  "data": {
    "app": "Google Chrome",
    "title": "GitHub - ActivityWatch/activitywatch"
  }
}
```

### C. 环境依赖

| 工具 | 版本要求 | 用途 |
|------|---------|------|
| Flutter SDK | ≥ 3.2 | 跨平台 UI 构建 |
| Dart | ≥ 3.2 | 编程语言 |
| Rust (nightly) | latest | 编译 aw-server-rust .so (仅 Android) |
| Android NDK | r25+ | Rust JNI 交叉编译 (仅 Android) |
| Visual Studio 2022 | 17.x | Windows C++ 悬浮窗编译 (可选) |
| Python | ≥ 3.9 | aw-server (Python 版，桌面端) |

### D. 版本规范

采用 `x.y.z` 语义：

| 位 | 含义 | 规则 |
|----|------|------|
| x | 大版本 | 开发阶段 = 0，首个正式版 = 1 |
| y | 开发 Phase | Phase 1 = 1, Phase 2 = 2, ... |
| z | 迭代次数 | 每轮修改/优化递增 |

```
0.0.1 → 设计阶段, 第 1 版
0.1.0 → Phase 1 开始
0.1.3 → Phase 1 第 3 次迭代
0.2.0 → Phase 2 开始
1.0.0 → 首个正式发布版
```

### E. 命名来源

"时光镜" — "时光"（时间）+ "镜"（镜子），寓意"照见时间流向的工具"。英文名 TimeLens = Time + Lens（透镜），表达"聚焦时间"的概念。
