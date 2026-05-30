# 时光镜 (TimeLens)

跨平台屏幕时间管理工具，基于 [ActivityWatch](https://github.com/ActivityWatch/activitywatch) 后端。

## 功能

- **实时计时悬浮窗**：mm:ss 格式显示当前前台应用使用时长
  - 30 分钟内绿色背景
  - 超过 30 分钟红色预警
- **今日使用统计**：Dashboard 面板展示各应用使用排行
- **跨平台**：Windows (Fluent UI) + Android (Material Design)

## 架构

```
TimeLens/
├── activitywatch/       # ActivityWatch 后端 (aw-server + watchers)
└── timelens_app/        # Flutter 前端
    └── lib/
        ├── core/
        │   ├── api_client.dart     # AW REST API 封装
        │   └── timer_service.dart  # 计时轮询逻辑
        └── features/
            ├── dashboard/          # 主面板
            └── overlay/            # 悬浮计时窗
```

## 前置条件

1. **启动 ActivityWatch 后端**
   ```bash
   cd activitywatch
   # 安装并运行 aw-server + aw-watcher-window
   ```

2. **安装 Flutter SDK** (>= 3.2)
   ```bash
   flutter pub get
   flutter run -d windows
   ```

## 开发状态

- [x] ActivityWatch API Client
- [x] 计时轮询服务
- [x] Dashboard 主面板
- [x] mm:ss 悬浮窗 (绿色/红色阈值)
- [ ] Windows 独立悬浮窗进程
- [ ] Android 端适配
