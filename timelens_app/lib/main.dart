/// 时光镜 — 跨平台屏幕时间管理
///
/// 基于 ActivityWatch 后端，提供 Android (Material Design)
/// 和 Windows (Fluent UI) 双端支持。
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/timer_service.dart';
import 'core/window_manager.dart' as wm;
import 'features/dashboard/dashboard_page.dart';
import 'features/overlay/overlay_window.dart';

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

  // 检查 aw-server 是否运行
  final serverRunning = await client.isServerRunning();

  // 启动计时器轮询
  timerService.start();

  runApp(TimeLensApp(
    client: client,
    timerService: timerService,
    windowManager: windowMgr,
    serverRunning: serverRunning,
  ));
}

Future<void> _initWindowsWindow() async {
  final w = await import('package:window_manager/window_manager.dart');
  await w.windowManager.ensureInitialized();
  await w.windowManager.waitUntilReadyToShow(
    const w.WindowOptions(
      size: Size(400, 700),
      minimumSize: Size(220, 60),
      center: true,
      title: '时光镜',
    ),
    () async {
      await w.windowManager.show();
      await w.windowManager.focus();
    },
  );
}

class TimeLensApp extends StatefulWidget {
  final AWClient client;
  final TimerService timerService;
  final wm.TimeLensWindowManager windowManager;
  final bool serverRunning;

  const TimeLensApp({
    super.key,
    required this.client,
    required this.timerService,
    required this.windowManager,
    required this.serverRunning,
  });

  @override
  State<TimeLensApp> createState() => _TimeLensAppState();
}

class _TimeLensAppState extends State<TimeLensApp> {
  late wm.WindowMode _mode = widget.windowManager.mode;

  @override
  void initState() {
    super.initState();
    widget.timerService.onStateChanged = (_) {
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.timerService.state;

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
      home: _mode == wm.WindowMode.mini
          ? _MiniModeView(
              state: state,
              onBack: _switchToDashboard,
            )
          : DashboardPage(
              client: widget.client,
              timerService: widget.timerService,
              onToggleMini: _switchToMini,
            ),
    );
  }

  Future<void> _switchToMini() async {
    await widget.windowManager.switchToMini();
    setState(() => _mode = wm.WindowMode.mini);
  }

  Future<void> _switchToDashboard() async {
    await widget.windowManager.switchToDashboard();
    setState(() => _mode = wm.WindowMode.dashboard);
  }
}

/// Mini 模式视图 — 悬浮计时窗 + 双击返回
class _MiniModeView extends StatelessWidget {
  final TimerState state;
  final VoidCallback onBack;

  const _MiniModeView({required this.state, required this.onBack});

  @override
  Widget build(BuildContext context) {
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
