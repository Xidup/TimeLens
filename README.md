# 时光镜 TimeLens

跨平台屏幕时间管理工具，基于 [ActivityWatch](https://github.com/ActivityWatch/activitywatch) 数据引擎。

> 让时间看得见 — 实时悬浮窗 + 原生 Dashboard + 多设备同步

## 功能

- **悬浮计时窗** — FPS 风格边角浮窗，mm:ss 实时显示当前应用使用时长
- **阈值提醒** — 绿/黄/红三色预警，每应用可独立配置（如飞书 180min vs 抖音 60min）
- **Dashboard** — 今日应用使用饼图 + 7 日趋势柱状图
- **跨平台** — Windows (Fluent UI) + Android (Material Design)，Flutter 一套代码

## 架构

```
TimeLens (Flutter UI)
    │
    ▼
aw-server-rust (REST API :5600)
    │
    ▼
aw-watcher-window / UsageStatsWatcher (数据采集)
```

详细设计见 [ARCHITECTURE.md](./ARCHITECTURE.md)

## 开发状态

`0.0.2` — 设计阶段完成，进入 Phase 1 开发

| Phase | 目标 | 状态 |
|-------|------|:---:|
| 1 | Windows MVP (悬浮窗 + Dashboard + 图表) | 🔜 |
| 2 | Android 移植 + 手动同步 | ⏳ |
| 3 | 通知 + 历史趋势 | ⏳ |
| 4 | 家庭管理 | ⏳ |

## 技术栈

| 层 | Windows | Android |
|----|---------|---------|
| 数据引擎 | aw-server-rust | aw-server-rust (JNI) |
| UI | Flutter + fluent_ui | Flutter + Material |
| 状态管理 | Riverpod | Riverpod |
| 图表 | fl_chart | fl_chart |
| 同步 | aw-sync + Syncthing (局域网) | 同左 |

## 前置条件

1. [ActivityWatch](https://activitywatch.net/) 后端运行中
2. [Flutter SDK](https://flutter.dev) ≥ 3.2

## 快速开始

```bash
git clone https://github.com/你的用户名/TimeLens.git
cd TimeLens/timelens_app

# Windows
flutter pub get
flutter run -d windows

# Android (Phase 2)
flutter run -d android
```

## 协议

- TimeLens 前端代码：自选协议
- aw-android 参考实现：MPL 2.0
- ActivityWatch 后端：MPL 2.0
