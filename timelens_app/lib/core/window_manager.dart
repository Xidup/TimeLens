/// Windows 平台 — 窗口模式管理
///
/// 支持两种模式切换：
/// 1. **Dashboard 模式**：完整主面板窗口
/// 2. **Mini 模式**：缩小为悬浮计时器，置顶无边框
///
/// Mini 模式悬浮窗固定在屏幕角落，锁定不可交互。
/// 通过系统托盘菜单返回 Dashboard。
///
/// 通过 [onModeChanged] 回调通知外部组件模式变化。
library;

import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口模式
enum WindowMode { dashboard, mini }

/// 悬浮窗屏幕位置
enum OverlayPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Windows 窗口管理器封装
///
/// 使用前需先调用 `windowManager.ensureInitialized()`（由 main.dart 完成）。
/// 所有操作只对 Windows 平台生效，非 Windows 平台调用为 no-op。
class TimeLensWindowManager {
  static const _dashboardSize = Size(400, 700);
  static const _miniSize = Size(220, 60);

  /// 悬浮窗距屏幕边缘的间距（逻辑像素）
  static const _edgeMargin = 8.0;

  /// 底部预留高度（避开任务栏，典型 48px）
  static const _bottomReserve = 48.0;

  WindowMode _mode = WindowMode.dashboard;

  /// 悬浮窗位置（默认左下角）
  OverlayPosition _overlayPosition = OverlayPosition.bottomLeft;

  /// 当前模式
  WindowMode get mode => _mode;

  /// 是否处于 Mini 悬浮窗模式
  bool get isMini => _mode == WindowMode.mini;

  /// 当前悬浮窗位置
  OverlayPosition get overlayPosition => _overlayPosition;

  // ── 回调 ──────────────────────────────────────────

  /// 模式切换回调（切换完成后调用）
  ///
  /// 用于联动 TimerService、Dashboard 等组件。
  void Function(WindowMode newMode)? onModeChanged;

  // ── 模式切换 ──────────────────────────────────────

  /// 切换到 Mini 悬浮窗模式
  ///
  /// 幂等：已是 Mini 模式则跳过。
  /// 根据 [overlayPosition] 计算屏幕坐标。
  /// 完成后调用 [onModeChanged]。
  Future<void> switchToMini() async {
    if (!Platform.isWindows) return;
    if (_mode == WindowMode.mini) return; // 幂等
    _mode = WindowMode.mini;

    await windowManager.setSize(_miniSize);
    await windowManager.setPosition(_calculateOffset());
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

  // ── 位置管理 ──────────────────────────────────────

  /// 设置悬浮窗位置并立即更新
  ///
  /// 供系统托盘菜单调用。
  Future<void> setOverlayPosition(OverlayPosition position) async {
    _overlayPosition = position;
    if (_mode == WindowMode.mini) {
      await windowManager.setPosition(_calculateOffset());
    }
  }

  /// 计算当前 [overlayPosition] 对应的屏幕坐标
  Offset _calculateOffset() {
    // 获取主屏幕逻辑分辨率
    final view = ui.PlatformDispatcher.instance.views.first;
    final screenW = view.physicalSize.width / view.devicePixelRatio;
    final screenH = view.physicalSize.height / view.devicePixelRatio;

    switch (_overlayPosition) {
      case OverlayPosition.topLeft:
        return const Offset(_edgeMargin, _edgeMargin);
      case OverlayPosition.topRight:
        return Offset(screenW - _miniSize.width - _edgeMargin, _edgeMargin);
      case OverlayPosition.bottomLeft:
        return Offset(
          _edgeMargin,
          screenH - _miniSize.height - _bottomReserve - _edgeMargin,
        );
      case OverlayPosition.bottomRight:
        return Offset(
          screenW - _miniSize.width - _edgeMargin,
          screenH - _miniSize.height - _bottomReserve - _edgeMargin,
        );
    }
  }

  // ── 生命周期 ──────────────────────────────────────

  void dispose() {
    onModeChanged = null;
  }
}
