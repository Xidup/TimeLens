/// 计时服务 — 追踪前台应用使用时间
///
/// 轮询 ActivityWatch API 获取当前窗口事件，
/// 计算今日各应用累计使用时长，驱动悬浮窗显示。
library;

import 'dart:async';
import 'api_client.dart';

/// 应用使用统计
class AppUsage {
  final String appName;
  final Duration todayTotal; // 今日累计
  final Duration currentSession; // 当前连续使用

  const AppUsage({
    required this.appName,
    this.todayTotal = Duration.zero,
    this.currentSession = Duration.zero,
  });
}

/// 计时器状态
enum TimerThreshold {
  /// 30 分钟内 — 绿色
  green,

  /// 超过 30 分钟 — 红色
  red,
}

/// 计时服务 — 通过 Riverpod Provider 暴露
class TimerService {
  final AWClient _client;

  /// 当前正在使用的应用
  String _currentApp = '';

  /// 各应用今日累计时长 (appName -> Duration)
  final Map<String, Duration> _todayUsage = {};

  /// 上次轮询时间
  DateTime _lastPoll = DateTime.now();

  /// 轮询间隔
  static const _pollInterval = Duration(seconds: 3);

  /// 红色阈值
  static const redThreshold = Duration(minutes: 30);

  Timer? _timer;

  /// 状态变化回调
  void Function(TimerState state)? onStateChanged;

  TimerService({required AWClient client}) : _client = client;

  /// 当前状态
  TimerState get state {
    final appName = _currentApp;
    final todayTotal = _todayUsage[appName] ?? Duration.zero;
    return TimerState(
      appName: appName,
      todayDuration: todayTotal,
      threshold: todayTotal >= redThreshold
          ? TimerThreshold.red
          : TimerThreshold.green,
    );
  }

  /// 启动轮询
  Future<void> start() async {
    // 立即执行一次
    await _poll();
    // 定期轮询
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  /// 停止轮询
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 单次轮询
  Future<void> _poll() async {
    try {
      final bucketId = await _client.findWindowBucketId();
      if (bucketId == null) return;

      // 获取今日事件
      final events = await _client.getTodayEvents(bucketId);
      if (events.isEmpty) return;

      // 最新事件 = 当前前台应用
      final latest = events.last;
      final appName = latest.app;

      // 计算各应用今日累计
      _computeTodayUsage(events);

      // 计算当前应用连续使用时长
      final now = DateTime.now();
      final elapsed = now.difference(_lastPoll);
      _lastPoll = now;

      if (appName == _currentApp) {
        // 同一应用，累加
        _todayUsage[appName] = (_todayUsage[appName] ?? Duration.zero) + elapsed;
      } else {
        _currentApp = appName;
        // 新应用，确保有记录
        _todayUsage.putIfAbsent(appName, () => Duration.zero);
      }

      onStateChanged?.call(state);
    } catch (_) {
      // 静默处理轮询错误
    }
  }

  /// 从事件列表计算今日各应用累计时长
  void _computeTodayUsage(List<AWEvent> events) {
    _todayUsage.clear();
    for (final event in events) {
      final app = event.app;
      _todayUsage.update(
        app,
        (d) => d + Duration(milliseconds: (event.duration * 1000).round()),
        ifAbsent: () => Duration(milliseconds: (event.duration * 1000).round()),
      );
    }
  }

  /// 格式化 duration 为 mm:ss
  static String formatMMSS(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 计时器状态
class TimerState {
  final String appName;
  final Duration todayDuration;
  final TimerThreshold threshold;

  const TimerState({
    required this.appName,
    required this.todayDuration,
    required this.threshold,
  });

  String get formatted => TimerService.formatMMSS(todayDuration);
}
