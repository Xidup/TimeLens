/// 时光镜 — 跨平台屏幕时间管理
///
/// 基于 ActivityWatch 后端，提供 Android (Material Design)
/// 和 Windows (Fluent UI) 双端支持。
///
/// **平台自适应**：
/// - Windows: FluentApp (`fluent_ui`) — Windows 11 风格
/// - Android/Linux/macOS: MaterialApp — Material Design 3 暗色主题
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:window_manager/window_manager.dart';

import 'core/api_client.dart';
import 'core/timer_service.dart';
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
  }

  // 初始化服务
  final client = AWClient();
  final timerService = TimerService(client: client);

  // 检查 aw-server 是否运行（用于初始 UI 状态）
  final serverRunning = await client.isServerRunning();

  // 启动计时器轮询（供悬浮窗使用）
  timerService.start();

  runApp(TimeLensApp(
    client: client,
    timerService: timerService,
    windowManager: windowMgr,
    initialServerRunning: serverRunning,
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

// ══════════════════════════════════════════════════════
// TimeLensApp — 平台自适应根组件
// ══════════════════════════════════════════════════════

class TimeLensApp extends StatefulWidget {
  final AWClient client;
  final TimerService timerService;
  final wm.TimeLensWindowManager windowManager;
  final bool initialServerRunning;

  const TimeLensApp({
    super.key,
    required this.client,
    required this.timerService,
    required this.windowManager,
    required this.initialServerRunning,
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

    // 模式切换回调：同步内部状态 + 通知后续 Task 1.8 交互层
    widget.windowManager.onModeChanged = (newMode) {
      if (!mounted) return;
      setState(() => _mode = newMode);
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
      return _MiniModeView(
        state: state,
        onBack: _switchToDashboard,
      );
    }
    return DashboardPage(
      client: widget.client,
      initialServerRunning: widget.initialServerRunning,
      onToggleMini: _switchToMini,
    );
  }

  // ── 模式切换方法 ───────────────────────────────────

  Future<void> _switchToMini() async {
    await widget.windowManager.switchToMini();
    // setState 由 onModeChanged 回调触发，此处不再重复调用
  }

  Future<void> _switchToDashboard() async {
    await widget.windowManager.switchToDashboard();
  }
}

// ══════════════════════════════════════════════════════
// Mini 模式视图
// ══════════════════════════════════════════════════════

/// Mini 模式视图 — 悬浮计时窗 + 双击返回
///
/// - 检测到桌面时（appName 为空）悬浮窗自动隐藏
/// - 应用切回前台时自动重新显示
/// - 双击回到 Dashboard 模式
class _MiniModeView extends StatelessWidget {
  final TimerState state;
  final VoidCallback onBack;

  const _MiniModeView({required this.state, required this.onBack});

  @override
  Widget build(BuildContext context) {
    // 桌面/锁屏时隐藏悬浮窗
    if (state.appName.isEmpty) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onDoubleTap: onBack,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: OverlayWindow(state: state),
        ),
      ),
    );
  }
}
