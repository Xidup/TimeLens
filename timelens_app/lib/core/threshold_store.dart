/// 阈值配置持久化
///
/// JSON 文件存储于应用数据目录。
library;

import 'dart:convert';
import 'dart:io' show File, Platform;

import 'threshold_config.dart';

/// 阈值配置 JSON 持久化
class ThresholdStore {
  static const _fileName = 'thresholds.json';

  /// 配置文件完整路径
  static String get _path {
    final dir = Platform.isWindows
        ? '${Platform.environment['APPDATA']}\\TimeLens'
        : '${Platform.environment['HOME']}/.config/timelens';
    return '$dir$_separator$_fileName';
  }

  static String get _separator => Platform.isWindows ? '\\' : '/';

  /// 从 JSON 文件加载配置列表
  ///
  /// 文件不存在时返回默认配置。
  /// 文件损坏时返回默认配置（静默降级）。
  static List<AppThresholdConfig> load() {
    try {
      final file = File(_path);
      if (!file.existsSync()) return AppThresholdConfig.defaults;

      final json = file.readAsStringSync();
      final list = jsonDecode(json) as List;
      return list
          .map((e) => AppThresholdConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return AppThresholdConfig.defaults;
    }
  }

  /// 保存配置列表到 JSON 文件
  ///
  /// 自动创建父目录。
  static void save(List<AppThresholdConfig> configs) {
    try {
      final file = File(_path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(configs),
      );
    } catch (_) {
      // 保存失败静默处理 — 不影响运行时功能
    }
  }
}
