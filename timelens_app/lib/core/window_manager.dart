/// Windows 平台 — 窗口模式管理
///
/// 支持两种模式切换：
/// 1. **Dashboard 模式**：完整主面板窗口
/// 2. **Mini 模式**：缩小为悬浮计时器，置顶无边框
///
/// 通过 [onModeChanged] 回调通知外部组件模式变化，
/// 用于联动 TimerService 的桌面检测暂停/恢复。
library;

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口模式
enum WindowMode { dashboard, mini }

/// Windows 窗口管理器封装
///
/// 使用前需先调用 `windowManager.ensureInitialized()`（由 main.dart 完成）。
/// 所有操作只对 Windows 平台生效，非 Windows 平台调用为 no-op。
class TimeLensWindowManager {
  static const _dashboardSize = Size(400, 700);
  static const _miniSize = Size(220, 60);

  WindowMode _mode = WindowMode.dashboard;

  /// 当前模式
  WindowMode get mode => _mode;

  /// 是否处于 Mini 悬浮窗模式
  bool get isMini => _mode == WindowMode.mini;

  // ── 回调 ──────────────────────────────────────────

  /// 模式切换回调（切换完成后调用，含初始模式）
  ///
  /// 用于联动 TimerService、Dashboard 等组件。
  void Function(WindowMode newMode)? onModeChanged;

  // ── 模式切换 ──────────────────────────────────────

  /// 切换到 Mini 悬浮窗模式
  ///
  /// 幂等：已是 Mini 模式则跳过。
  /// 完成后调用 [onModeChanged]。
  Future<void> switchToMini() async {
    if (!Platform.isWindows) return;
    if (_mode == WindowMode.mini) return; // 幂等
    _mode = WindowMode.mini;
    await windowManager.setSize(_miniSize);
    await windowManager.setPosition(const Offset(16, 16)); // 默认左上角
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    onModeChanged?.call(_mode);
  }

  /// 切换到 Dashboard 模式
  ///
  /// 幂等：已是 Dashboard 模式则跳过。
  /// 完成后调用 [onModeChanged]。
  Future<void> switchToDashboard() async {
    if (!Platform.isWindows) return;
    if (_mode == WindowMode.dashboard) return; // 幂等
    _mode = WindowMode.dashboard;
    await windowManager.setSize(_dashboardSize);
    await windowManager.center();
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setTitle('时光镜');
    onModeChanged?.call(_mode);
  }

  /// 切换模式（Dashboard ↔ Mini）
  Future<void> toggle() async {
    if (_mode == WindowMode.dashboard) {
      await switchToMini();
    } else {
      await switchToDashboard();
    }
  }

  // ── 生命周期 ──────────────────────────────────────

  void dispose() {
    onModeChanged = null;
  }
}
