/// Windows 平台 — 窗口模式管理
///
/// 支持两种模式切换：
/// 1. **Dashboard 模式**：完整主面板窗口
/// 2. **Mini 模式**：缩小为悬浮计时器，置顶无边框
library;

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口模式
enum WindowMode { dashboard, mini }

/// Windows 窗口管理器封装
class TimeLensWindowManager {
  static const _dashboardSize = Size(400, 700);
  static const _miniSize = Size(220, 60);

  WindowMode _mode = WindowMode.dashboard;

  WindowMode get mode => _mode;

  /// 切换到 Mini 悬浮窗模式
  Future<void> switchToMini() async {
    if (!Platform.isWindows) return;
    _mode = WindowMode.mini;
    await windowManager.setSize(_miniSize);
    await windowManager.setPosition(const Offset(16, 16)); // 左上角
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  }

  /// 切换到 Dashboard 模式
  Future<void> switchToDashboard() async {
    if (!Platform.isWindows) return;
    _mode = WindowMode.dashboard;
    await windowManager.setSize(_dashboardSize);
    await windowManager.center();
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setTitle('时光镜');
  }

  /// 切换模式
  Future<void> toggle() async {
    if (_mode == WindowMode.dashboard) {
      await switchToMini();
    } else {
      await switchToDashboard();
    }
  }

  void dispose() {}
}
