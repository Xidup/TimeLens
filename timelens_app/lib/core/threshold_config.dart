/// 应用阈值配置 — 每应用可自定义颜色规则
///
/// 定义多级阈值阶梯（绿/黄/红），支持全局默认 + 单应用覆盖。
/// Task 1.9 将在此基础上添加配置 UI。
library;

import 'package:flutter/painting.dart';

/// 阈值颜色级别
enum TimerThreshold {
  /// 0～30 分钟 — 文字绿色
  green,

  /// 30～60 分钟 — 文字黄色
  yellow,

  /// >60 分钟 — 文字红色
  red,
}

/// 一个阈值阶梯
///
/// 定义从上一个阶梯上限到此阶梯上限之间的颜色。
class ThresholdStep {
  /// 此阶梯的时长上限（不含）
  ///
  /// 最后一个阶梯可用 [infinity] 表示无上限。
  final Duration maxDuration;

  /// 文字颜色
  final Color textColor;

  const ThresholdStep({
    required this.maxDuration,
    required this.textColor,
  });

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'maxDuration': maxDuration == infinity
            ? -1
            : maxDuration.inSeconds,
        'textColor': textColor.toARGB32(),
      };

  /// 从 JSON 反序列化
  factory ThresholdStep.fromJson(Map<String, dynamic> json) {
    final seconds = json['maxDuration'] as int;
    return ThresholdStep(
      maxDuration: seconds == -1 ? infinity : Duration(seconds: seconds),
      textColor: Color(json['textColor'] as int),
    );
  }

  /// 无上限哨兵值
  static const infinity = Duration(days: 9999);
}

/// 每应用阈值配置
///
/// [appPattern] 支持：
/// - `"*"` — 匹配所有应用（默认规则，必须存在）
/// - `"Feishu"` — 包含匹配（大小写不敏感）
class AppThresholdConfig {
  /// 应用匹配模式
  final String appPattern;

  /// 阈值阶梯列表，按 [ThresholdStep.maxDuration] 升序排列
  final List<ThresholdStep> steps;

  const AppThresholdConfig({
    required this.appPattern,
    required this.steps,
  });

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'appPattern': appPattern,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  /// 从 JSON 反序列化
  factory AppThresholdConfig.fromJson(Map<String, dynamic> json) {
    return AppThresholdConfig(
      appPattern: json['appPattern'] as String,
      steps: (json['steps'] as List)
          .map((s) => ThresholdStep.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 判断此规则是否匹配给定应用名
  bool matches(String appName) {
    if (appPattern == '*') return true;
    return appName.toLowerCase().contains(appPattern.toLowerCase());
  }

  /// 根据时长查找对应的阈值颜色
  ///
  /// 遍历 [steps]，返回第一个 [maxDuration] 大于 [duration] 的阶梯。
  /// 若 duration 超出所有阶梯，返回最后一个阶梯。
  TimerThreshold thresholdFor(Duration duration) {
    for (int i = 0; i < steps.length; i++) {
      if (duration < steps[i].maxDuration) {
        return _thresholdAtIndex(i);
      }
    }
    return _thresholdAtIndex(steps.length - 1);
  }

  /// 根据时长查找对应的文字颜色
  Color textColorFor(Duration duration) {
    for (int i = 0; i < steps.length; i++) {
      if (duration < steps[i].maxDuration) {
        return steps[i].textColor;
      }
    }
    return steps.last.textColor;
  }

  /// 阶梯索引 → 阈值枚举
  TimerThreshold _thresholdAtIndex(int index) {
    // 默认映射：0=green, 1=yellow, 最后=red
    if (index == 0) return TimerThreshold.green;
    if (index == steps.length - 1) return TimerThreshold.red;
    return TimerThreshold.yellow;
  }

  // ── 预置规则 ──────────────────────────────────────────

  /// 默认规则（全局兜底）
  ///
  /// 0～30 分钟 绿色，30～60 分钟 黄色，>60 分钟 红色。
  static AppThresholdConfig get defaultRule => const AppThresholdConfig(
        appPattern: '*',
        steps: [
          ThresholdStep(
            maxDuration: Duration(minutes: 30),
            textColor: Color(0xFF66BB6A), // Green 400
          ),
          ThresholdStep(
            maxDuration: Duration(minutes: 60),
            textColor: Color(0xFFF9A825), // Yellow 600
          ),
          ThresholdStep(
            maxDuration: ThresholdStep.infinity,
            textColor: Color(0xFFEF5350), // Red 400
          ),
        ],
      );

  /// 默认配置列表示例（含工作/娱乐应用覆盖）
  ///
  /// Task 1.9 的配置 UI 将读写此列表。
  static List<AppThresholdConfig> get defaults => [defaultRule];

  /// 从配置列表中查找匹配当前应用的规则
  ///
  /// 优先返回精确匹配，否则返回默认规则。
  static AppThresholdConfig find(
    List<AppThresholdConfig> configs,
    String appName,
  ) {
    // 先找精确（非通配）匹配
    for (final c in configs) {
      if (c.appPattern != '*' && c.matches(appName)) return c;
    }
    // 回退到默认
    for (final c in configs) {
      if (c.appPattern == '*') return c;
    }
    // 兜底（不应到达）
    return defaultRule;
  }
}
