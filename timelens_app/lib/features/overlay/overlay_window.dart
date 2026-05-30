/// 悬浮计时窗 — 前台应用使用时间实时显示
///
/// mm:ss 格式，30 分钟内绿色背景，超时红色背景。
/// 在 Windows 上作为独立顶层窗口运行。
library;

import 'package:flutter/material.dart';
import '../../core/timer_service.dart';

/// 悬浮计时窗
///
/// 显示当前应用名称和今日使用时长。
/// 背景色根据阈值自动切换：
/// - 绿色: ≤ 30 分钟
/// - 红色: > 30 分钟
class OverlayWindow extends StatelessWidget {
  final TimerState state;

  const OverlayWindow({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final isGreen = state.threshold == TimerThreshold.green;

    return Container(
      decoration: BoxDecoration(
        color: isGreen
            ? const Color(0xFF2E7D32) // Material Green 800
            : const Color(0xFFC62828), // Material Red 800
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 应用图标占位
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

          // 阈值指示器
          if (!isGreen) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 根据应用名返回图标
  IconData _appIcon(String appName) {
    final lower = appName.toLowerCase();
    if (lower.contains('chrome') || lower.contains('edge') || lower.contains('firefox')) {
      return Icons.language;
    } else if (lower.contains('code') || lower.contains('studio') || lower.contains('idea')) {
      return Icons.code;
    } else if (lower.contains('terminal') || lower.contains('cmd')) {
      return Icons.terminal;
    } else if (lower.contains('explorer') || lower.contains('finder')) {
      return Icons.folder;
    } else if (lower.contains('word') || lower.contains('excel') || lower.contains('ppt')) {
      return Icons.description;
    } else {
      return Icons.desktop_windows;
    }
  }
}

/// 全屏覆盖模式 — 用于在主窗口中以内嵌方式显示计时器
///
/// 适用于在主应用内预览悬浮窗效果
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
