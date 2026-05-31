/// 悬浮计时窗 — 前台应用使用时间实时显示
///
/// mm:ss 格式，三档阈值颜色：
/// - 绿色 (0-30m)：安全使用
/// - 黄色 (30-60m)：注意休息
/// - 红色 (>60m)：超时警告
///
/// 在 Windows 上作为独立顶层窗口运行。
/// FPS 透明风格视觉由 Task 1.5 实现。
library;

import 'package:flutter/material.dart';
import '../../core/timer_service.dart';

/// 悬浮计时窗
///
/// 显示当前应用名称和今日使用时长。
/// 背景色根据阈值自动切换：
/// - 绿色: ≤ 30 分钟
/// - 黄色: 30～60 分钟
/// - 红色: > 60 分钟
class OverlayWindow extends StatelessWidget {
  final TimerState state;

  const OverlayWindow({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final threshold = state.threshold;
    final bgColor = _bgColorFor(threshold);
    final indicatorColor = _indicatorColorFor(threshold);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 应用图标
          Icon(
            _appIcon(state.appName),
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(width: 8),

          // 应用名 + 计时
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.appName.isEmpty ? '--' : state.appName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                state.formatted,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
            ],
          ),

          // 阈值指示器（黄色和红色时显示）
          if (threshold != TimerThreshold.green) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: indicatorColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 阈值 → 背景色
  Color _bgColorFor(TimerThreshold t) {
    switch (t) {
      case TimerThreshold.green:
        return const Color(0xFF2E7D32); // Material Green 800
      case TimerThreshold.yellow:
        return const Color(0xFFF57F17); // Material Yellow 900
      case TimerThreshold.red:
        return const Color(0xFFC62828); // Material Red 800
    }
  }

  /// 阈值 → 指示器颜色
  Color _indicatorColorFor(TimerThreshold t) {
    switch (t) {
      case TimerThreshold.green:
        return const Color(0xFF66BB6A);
      case TimerThreshold.yellow:
        return const Color(0xFFFFEB3B); // Yellow accent
      case TimerThreshold.red:
        return Colors.white;
    }
  }

  /// 根据应用名返回图标
  IconData _appIcon(String appName) {
    final lower = appName.toLowerCase();
    if (lower.contains('chrome') ||
        lower.contains('edge') ||
        lower.contains('firefox')) {
      return Icons.language;
    } else if (lower.contains('code') ||
        lower.contains('studio') ||
        lower.contains('idea')) {
      return Icons.code;
    } else if (lower.contains('terminal') || lower.contains('cmd')) {
      return Icons.terminal;
    } else if (lower.contains('explorer') || lower.contains('finder')) {
      return Icons.folder;
    } else if (lower.contains('word') ||
        lower.contains('excel') ||
        lower.contains('ppt')) {
      return Icons.description;
    } else {
      return Icons.desktop_windows;
    }
  }
}

/// 全屏覆盖模式 — 用于在主窗口中以内嵌方式显示计时器
class InlineTimer extends StatelessWidget {
  final TimerState state;

  const InlineTimer({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OverlayWindow(state: state),
    );
  }
}
