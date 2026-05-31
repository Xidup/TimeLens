/// 计时服务 — 事件驱动式前台应用计时
///
/// **架构（决策 7）**：
/// - 本地 Dart Timer 每秒自增，驱动 UI 逐秒刷新
/// - 每 5 秒轮询 aw-server API 检测窗口是否切换
/// - 切换时丢弃本地计数，从 API 读取新应用今日累计作为新起点
/// - 不做校准，几秒误差可忽略
///
/// **桌面检测（决策 7/8）**：
/// - 当 aw-server 报告 explorer.exe 或无焦点窗口时自动暂停计时
/// - Mini 模式下悬浮窗随之隐藏
/// - 应用切回前台时自动恢复
///
/// **阈值（决策 8）**：
/// - 三档：绿(0-30m) / 黄(30-60m) / 红(>60m)
/// - 支持每应用自定义阈值规则（[AppThresholdConfig]）
/// - 配置 UI 由 Task 1.9 实现
library;

import 'dart:async';

import 'api_client.dart';
import 'threshold_config.dart';

export 'threshold_config.dart' show TimerThreshold, AppThresholdConfig, ThresholdStep;

/// 计时器状态（对外暴露的只读快照）
class TimerState {
  /// 当前前台应用名（空字符串表示未初始化）
  final String appName;

  /// 今日累计时长 = API 权威值 + 本地增量
  final Duration todayDuration;

  /// 当前阈值级别
  final TimerThreshold threshold;

  const TimerState({
    required this.appName,
    required this.todayDuration,
    required this.threshold,
  });

  /// mm:ss 格式化
  String get formatted => TimerService.formatMMSS(todayDuration);

  /// 空状态（服务未启动时）
  static const empty = TimerState(
    appName: '',
    todayDuration: Duration.zero,
    threshold: TimerThreshold.green,
  );
}

/// 计时服务
///
/// 通过回调 [onStateChanged] 向 UI 层推送状态变化。
/// 每秒触发一次（本地 tick），切换应用时也触发。
class TimerService {
  final AWClient _client;

  // ── 内部状态 ──────────────────────────────────────

  /// 当前前台应用名
  String _currentApp = '';

  /// 当前应用的今日累计时长（从 API 获取的权威值）
  Duration _todayTotal = Duration.zero;

  /// 本地 Timer 已 tick 的秒数
  int _sessionSeconds = 0;

  /// 暂停标志（桌面/锁屏时由 UI 层设置）
  bool _paused = false;

  /// 阈值规则列表
  final List<AppThresholdConfig> _configs;

  // ── 定时器 ────────────────────────────────────────

  /// 每秒自增的本地 Timer
  Timer? _ticker;

  /// 每 5 秒检测窗口切换的 Timer
  Timer? _detectTimer;

  /// 检测间隔
  static const _detectInterval = Duration(seconds: 5);

  /// 桌面应用名模式（aw-watcher-window 无焦点窗口时报告的值）
  static const _desktopPatterns = [
    'explorer.exe',
    'applicationframehost.exe',
    'shellexperiencehost.exe',
    'searchapp.exe',
    'systemsettings.exe',
  ];

  // ── 回调 ──────────────────────────────────────────

  /// 状态变化回调（每秒 + 切换时触发）
  void Function(TimerState state)? onStateChanged;

  // ── 构造 ──────────────────────────────────────────

  TimerService({
    required AWClient client,
    List<AppThresholdConfig>? configs,
  })  : _client = client,
        _configs = configs ?? AppThresholdConfig.defaults;

  // ── 公开属性 ──────────────────────────────────────

  /// 当前状态快照
  TimerState get state {
    if (_currentApp.isEmpty) return TimerState.empty;
    final total = _todayTotal + Duration(seconds: _sessionSeconds);
    final config = AppThresholdConfig.find(_configs, _currentApp);
    return TimerState(
      appName: _currentApp,
      todayDuration: total,
      threshold: config.thresholdFor(total),
    );
  }

  /// 当前阈值配置列表（Task 1.9 配置 UI 读写）
  List<AppThresholdConfig> get configs => List.unmodifiable(_configs);

  // ── 生命周期 ──────────────────────────────────────

  /// 启动计时服务
  ///
  /// 1. 从 API 获取当前应用 + 今日累计时长
  /// 2. 启动本地 1s ticker
  /// 3. 启动 5s 检测 timer
  Future<void> start() async {
    await _initFromAPI();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _detectTimer = Timer.periodic(_detectInterval, (_) => _onDetect());

    // 首次通知
    onStateChanged?.call(state);
  }

  /// 停止计时服务
  void stop() {
    _ticker?.cancel();
    _detectTimer?.cancel();
    _ticker = null;
    _detectTimer = null;
  }

  /// 是否正在运行
  bool get isRunning => _ticker != null;

  /// 暂停本地计时（桌面/锁屏时由 UI 层调用）
  ///
  /// 暂停后 [_onTick] 不再自增，但 [_onDetect] 继续运行以检测应用切换。
  void pause() => _paused = true;

  /// 恢复本地计时
  void resume() => _paused = false;

  // ── 内部：每秒 tick ───────────────────────────────

  /// 本地 Timer 每秒回调
  ///
  /// 纯本地操作：自增 [_sessionSeconds]，不访问网络。
  void _onTick() {
    if (_currentApp.isEmpty || _paused) return;
    _sessionSeconds++;
    onStateChanged?.call(state);
  }

  // ── 内部：5 秒检测 ────────────────────────────────

  /// 每 5 秒检测窗口是否切换
  ///
  /// 同一应用 → 不做任何操作（Timer 继续跑）
  /// 切到桌面 → 暂停计时 + 清空应用名（Mini 模式下悬浮窗隐藏）
  /// 切换应用 → 丢弃本地计数 → 从 API 读取新应用今日累计
  Future<void> _onDetect() async {
    try {
      final bucketId = await _client.findWindowBucketId();
      if (bucketId == null) return;

      final events = await _client.getEvents(bucketId, limit: 1);
      if (events.isEmpty) return;

      final latest = events.last;
      final newApp = latest.app;

      // ── 桌面检测：暂停计时 ──
      if (_isDesktopApp(newApp)) {
        // 已在桌面 → 不重复通知
        if (_currentApp.isEmpty) return;
        _sessionSeconds = 0;
        _currentApp = '';
        _paused = true;
        onStateChanged?.call(state);
        return;
      }

      // ── 同一应用 — 不操作 ──
      if (newApp == _currentApp) return;

      // ── 应用切换 — 丢弃本地计数，恢复暂停 ──
      _sessionSeconds = 0;
      _paused = false; // 从桌面恢复时也要重置
      _currentApp = newApp;

      // 从 API 读取新应用的今日累计
      await _loadAppTodayTotal(newApp, bucketId);

      onStateChanged?.call(state);
    } catch (_) {
      // 静默处理检测错误（aw-server 可能暂时不可用）
    }
  }

  /// 判断是否为桌面应用（无焦点窗口时 aw-server 报告的值）
  bool _isDesktopApp(String appName) {
    final lower = appName.toLowerCase();
    return _desktopPatterns.any((p) => lower.startsWith(p));
  }

  // ── 内部：API 交互 ────────────────────────────────

  /// 初始化：从 API 获取当前应用 + 今日累计
  Future<void> _initFromAPI() async {
    try {
      final bucketId = await _client.findWindowBucketId();
      if (bucketId == null) return;

      final events = await _client.getEvents(bucketId, limit: 1);
      if (events.isEmpty) return;

      _currentApp = events.last.app;
      await _loadAppTodayTotal(_currentApp, bucketId);
    } catch (_) {
      // 初始化失败保持空状态
    }
  }

  /// 计算指定应用今日累计时长（从今日事件列表聚合）
  Future<void> _loadAppTodayTotal(String appName, String bucketId) async {
    try {
      final events = await _client.getTodayEvents(bucketId);
      double totalSeconds = 0;
      for (final e in events) {
        if (e.app == appName) {
          totalSeconds += e.duration;
        }
      }
      _todayTotal = Duration(milliseconds: (totalSeconds * 1000).round());
    } catch (_) {
      _todayTotal = Duration.zero;
    }
  }

  // ── 工具方法 ──────────────────────────────────────

  /// 格式化 Duration 为 mm:ss（超过 1 小时显示 h:mm:ss）
  static String formatMMSS(Duration d) {
    if (d.inHours > 0) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
