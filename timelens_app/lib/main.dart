/// 时光镜 — 跨平台屏幕时间管理
///
/// 基于 ActivityWatch 后端，提供 Android (Material Design)
/// 和 Windows (Fluent UI) 双端支持。
///
/// **平台自适应**：
/// - Windows: FluentApp (`fluent_ui`) + 系统托盘
/// - Android/Linux/macOS: MaterialApp
///
/// **Mini 模式**：
/// - 悬浮窗锁定在屏幕角落，无交互（双击/拖动/右键均不响应）
/// - 通过系统托盘菜单「打开面板」返回 Dashboard
/// - 默认位置：左下角
library;

import 'dart:io' show Platform, exit;

import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'core/api_client.dart';
import 'core/timer_service.dart';
import 'core/threshold_store.dart';
import 'core/window_manager.dart' as wm;
import 'features/dashboard/dashboard_page.dart';
import 'features/overlay/overlay_window.dart';

// ══════════════════════════════════════════════════════
// 应用入口
// ══════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows: 初始化窗口管理器
  final windowMgr = wm.TimeLensWindowManager();
  if (Platform.isWindows) {
    await _initWindowsWindow();
    await _initTray(windowMgr);
  }

  // 初始化服务
  final client = AWClient();
  final configs = ThresholdStore.load();
  final timerService = TimerService(client: client, configs: configs);

  // 检查 aw-server 是否运行（用于初始 UI 状态）
  final serverRunning = await client.isServerRunning();

  // 启动计时器轮询（供悬浮窗使用）
  timerService.start();

  runApp(TimeLensApp(
    client: client,
    timerService: timerService,
    windowManager: windowMgr,
    initialServerRunning: serverRunning,
    thresholdConfigs: configs,
  ));
}

/// Windows 窗口初始化
Future<void> _initWindowsWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(400, 700),
      minimumSize: Size(220, 60),
      center: true,
      title: '时光镜',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

/// 系统托盘初始化
Future<void> _initTray(wm.TimeLensWindowManager windowMgr) async {
  await trayManager.setIcon('assets/tray_icon.ico');
  await trayManager.setToolTip('时光镜');
  await _updateTrayMenu(windowMgr);
}

/// 根据当前模式构建托盘菜单
///
/// - Mini 模式：显示「打开面板」
/// - Dashboard 模式：显示「切换到悬浮窗」
Future<void> _updateTrayMenu(wm.TimeLensWindowManager windowMgr) async {
  final isMini = windowMgr.isMini;

  final menu = Menu(
    items: [
      // ── 主操作 ──
      if (isMini)
        MenuItem(
          label: '打开面板',
          onClick: (_) => windowMgr.switchToDashboard(),
        )
      else
        MenuItem(
          label: '切换到悬浮窗',
          onClick: (_) => windowMgr.switchToMini(),
        ),

      MenuItem.separator(),

      // ── 悬浮窗位置 ──
      MenuItem(
        label: '悬浮窗位置',
        submenu: Menu(
          items: [
            MenuItem(
              label: '左上角',
              onClick: (_) =>
                  windowMgr.setOverlayPosition(wm.OverlayPosition.topLeft),
            ),
            MenuItem(
              label: '右上角',
              onClick: (_) =>
                  windowMgr.setOverlayPosition(wm.OverlayPosition.topRight),
            ),
            MenuItem(
              label: '左下角  ✓',
              onClick: (_) =>
                  windowMgr.setOverlayPosition(wm.OverlayPosition.bottomLeft),
            ),
            MenuItem(
              label: '右下角',
              onClick: (_) =>
                  windowMgr.setOverlayPosition(wm.OverlayPosition.bottomRight),
            ),
          ],
        ),
      ),

      MenuItem.separator(),

      // ── 退出 ──
      MenuItem(
        label: '退出',
        onClick: (_) async {
          await trayManager.destroy();
          // ignore: use_build_context_synchronously — main() context
          exit(0);
        },
      ),
    ],
  );

  await trayManager.setContextMenu(menu);
}

// ══════════════════════════════════════════════════════
// TimeLensApp — 平台自适应根组件
// ══════════════════════════════════════════════════════

class TimeLensApp extends StatefulWidget {
  final AWClient client;
  final TimerService timerService;
  final wm.TimeLensWindowManager windowManager;
  final bool initialServerRunning;
  final List<AppThresholdConfig> thresholdConfigs;

  const TimeLensApp({
    super.key,
    required this.client,
    required this.timerService,
    required this.windowManager,
    required this.initialServerRunning,
    required this.thresholdConfigs,
  });

  @override
  State<TimeLensApp> createState() => _TimeLensAppState();
}

class _TimeLensAppState extends State<TimeLensApp> {
  late wm.WindowMode _mode = widget.windowManager.mode;

  @override
  void initState() {
    super.initState();

    // Timer 每秒 tick → 刷新 UI（悬浮窗计时数字）
    widget.timerService.onStateChanged = (_) {
      if (mounted) setState(() {});
    };

    // 模式切换 → 同步状态 + 更新托盘菜单
    widget.windowManager.onModeChanged = (newMode) {
      if (!mounted) return;
      setState(() => _mode = newMode);
      _updateTrayMenu(widget.windowManager);
    };
  }

  @override
  void dispose() {
    widget.windowManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.timerService.state;

    // 平台自适应：Windows → FluentApp，其余 → MaterialApp
    if (Platform.isWindows) {
      return _buildFluentApp(state);
    }
    return _buildMaterialApp(state);
  }

  // ── Windows: Fluent UI ─────────────────────────────

  Widget _buildFluentApp(TimerState state) {
    return fluent.FluentApp(
      title: '时光镜',
      debugShowCheckedModeBanner: false,
      theme: fluent.FluentThemeData(
        brightness: Brightness.dark,
        accentColor: fluent.Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      ),
      home: _buildHome(state),
    );
  }

  // ── Android / 其他平台: Material Design ────────────

  Widget _buildMaterialApp(TimerState state) {
    return MaterialApp(
      title: '时光镜',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF0F3460),
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0F3460),
          secondary: Color(0xFFE94560),
          surface: Color(0xFF16213E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16213E),
          elevation: 0,
        ),
      ),
      home: _buildHome(state),
    );
  }

  // ── 模式路由 ───────────────────────────────────────

  Widget _buildHome(TimerState state) {
    if (_mode == wm.WindowMode.mini) {
      return _MiniModeView(state: state);
    }
    return DashboardPage(
      client: widget.client,
      initialServerRunning: widget.initialServerRunning,
      thresholdConfigs: widget.thresholdConfigs,
      onToggleMini: _switchToMini,
      onConfigsChanged: _onConfigsChanged,
    );
  }

  /// 配置变更 → 持久化 + 通知 TimerService
  void _onConfigsChanged(List<AppThresholdConfig> newConfigs) {
    ThresholdStore.save(newConfigs);
    widget.timerService.updateConfigs(newConfigs);
  }

  // ── 模式切换方法 ───────────────────────────────────

  Future<void> _switchToMini() async {
    await widget.windowManager.switchToMini();
    // setState 由 onModeChanged 回调触发
  }
}

// ══════════════════════════════════════════════════════
// Mini 模式视图 — 锁定悬浮窗
// ══════════════════════════════════════════════════════

/// Mini 模式视图 — 锁定悬浮计时窗
///
/// **无任何交互**：不响应双击、拖动、长按、右键。
/// 返回 Dashboard 的唯一途径：系统托盘「打开面板」。
///
/// - 检测到桌面时（appName 为空）悬浮窗自动隐藏
/// - 应用切回前台时自动重新显示
class _MiniModeView extends StatelessWidget {
  final TimerState state;

  const _MiniModeView({required this.state});

  @override
  Widget build(BuildContext context) {
    // 桌面/锁屏时隐藏悬浮窗
    if (state.appName.isEmpty) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: OverlayWindow(state: state),
      ),
    );
  }
}
