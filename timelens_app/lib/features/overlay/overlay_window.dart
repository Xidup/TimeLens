/// 悬浮计时窗 — FPS 透明风格
///
/// 显示当前前台应用名和今日累计时长 (mm:ss)。
/// 背景透明，仅计时数字颜色随阈值变化：
/// - 绿色 #66BB6A (0-30m)
/// - 黄色 #F9A825 (30-60m)
/// - 红色 #EF5350 (>60m)
///
/// 视觉规格（决策 8）：
/// - 背景：透明（可配透明度），圆角 6px
/// - 应用名：白色 70%，11sp
/// - 计时数字：等宽字体，字间距 2px
/// - 桌面时隐藏（由 TimerService pause/resume 控制）
library;

import 'package:flutter/material.dart';
import '../../core/timer_service.dart';

/// FPS 风格悬浮计时窗
///
/// [backgroundOpacity] 保留为 UI 接口，后续设置页可调。
class OverlayWindow extends StatelessWidget {
  final TimerState state;

  /// 背景透明度 0.0~1.0，0 = 全透明（默认），1 = 全黑
  final double backgroundOpacity;

  const OverlayWindow({
    super.key,
    required this.state,
    this.backgroundOpacity = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final threshold = state.threshold;
    final textColor = _textColorFor(threshold);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: backgroundOpacity),
        borderRadius: BorderRadius.circular(6),
        boxShadow: backgroundOpacity > 0.05
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 应用图标
          Icon(
            _appIcon(state.appName),
            color: Colors.white.withValues(alpha: 0.7),
            size: 16,
          ),
          const SizedBox(width: 6),

          // 应用名 + 计时数字
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.appName.isEmpty ? '--' : state.appName,
                style: const TextStyle(
                  color: Color(0xB3FFFFFF), // 白色 70%
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                state.formatted,
                style: TextStyle(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 阈值 → 文字颜色
  Color _textColorFor(TimerThreshold t) {
    switch (t) {
      case TimerThreshold.green:
        return const Color(0xFF66BB6A);
      case TimerThreshold.yellow:
        return const Color(0xFFF9A825);
      case TimerThreshold.red:
        return const Color(0xFFEF5350);
    }
  }

  /// 应用名 → 图标
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

/// 内嵌模式 — Dashboard 中预览悬浮窗外观
class InlineTimer extends StatelessWidget {
  final TimerState state;

  const InlineTimer({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OverlayWindow(state: state, backgroundOpacity: 0.4),
    );
  }
}
