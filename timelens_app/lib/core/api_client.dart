/// ActivityWatch REST API Client
///
/// 封装与 aw-server 的 HTTP 通信，提供类型安全的 Dart 接口。
library;

import 'package:dio/dio.dart';

/// 单个时间追踪事件
class AWEvent {
  final int? id;
  final DateTime timestamp;
  final double duration; // 秒
  final Map<String, dynamic> data;

  const AWEvent({
    this.id,
    required this.timestamp,
    required this.duration,
    required this.data,
  });

  factory AWEvent.fromJson(Map<String, dynamic> json) => AWEvent(
        id: json['id'] as int?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        duration: (json['duration'] as num).toDouble(),
        data: Map<String, dynamic>.from(json['data'] as Map? ?? {}),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'duration': duration,
        'data': data,
      };

  /// 应用名称（从 data 中提取）
  String get app => data['app'] as String? ?? 'Unknown';

  /// 窗口标题
  String get title => data['title'] as String? ?? '';
}

/// 数据桶元信息
class AWBucket {
  final String id;
  final String type;
  final String client;
  final String hostname;
  final DateTime? lastUpdated;

  const AWBucket({
    required this.id,
    required this.type,
    required this.client,
    required this.hostname,
    this.lastUpdated,
  });

  factory AWBucket.fromJson(String id, Map<String, dynamic> json) => AWBucket(
        id: id,
        type: json['type'] as String? ?? '',
        client: json['client'] as String? ?? '',
        hostname: json['hostname'] as String? ?? '',
        lastUpdated: json['last_updated'] != null
            ? DateTime.parse(json['last_updated'] as String)
            : null,
      );
}

/// 查询结果中的时间段聚合
class AWQueryResult {
  final double duration;
  final Map<String, dynamic> data;

  const AWQueryResult({required this.duration, required this.data});

  factory AWQueryResult.fromJson(Map<String, dynamic> json) => AWQueryResult(
        duration: (json['duration'] as num).toDouble(),
        data: Map<String, dynamic>.from(json['data'] as Map? ?? {}),
      );
}

/// ActivityWatch REST API Client
class AWClient {
  final Dio _dio;

  AWClient({String baseUrl = 'http://localhost:5600'})
      : _dio = Dio(BaseOptions(
          baseUrl: '$baseUrl/api/0',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ));

  /// 获取服务器信息
  Future<Map<String, dynamic>> getInfo() async {
    final res = await _dio.get('/info');
    return res.data as Map<String, dynamic>;
  }

  /// 获取所有数据桶
  Future<List<AWBucket>> getBuckets() async {
    final res = await _dio.get('/buckets/');
    final map = res.data as Map<String, dynamic>;
    return map.entries.map((e) => AWBucket.fromJson(e.key, e.value)).toList();
  }

  /// 获取窗口监视器桶 ID
  ///
  /// 模式: `aw-watcher-window_{hostname}`
  Future<String?> findWindowBucketId() async {
    final buckets = await getBuckets();
    for (final b in buckets) {
      if (b.id.startsWith('aw-watcher-window_')) return b.id;
    }
    return null;
  }

  /// 获取事件列表
  Future<List<AWEvent>> getEvents(
    String bucketId, {
    int limit = 100,
    DateTime? start,
    DateTime? end,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
    };
    if (start != null) params['start'] = start.toUtc().toIso8601String();
    if (end != null) params['end'] = end.toUtc().toIso8601String();
    final res = await _dio.get('/buckets/$bucketId/events', queryParameters: params);
    final list = res.data as List;
    return list.map((e) => AWEvent.fromJson(e)).toList();
  }

  /// 获取今日事件
  Future<List<AWEvent>> getTodayEvents(String bucketId) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return getEvents(bucketId, limit: 1000, start: todayStart, end: now);
  }

  /// 查询时间段（聚合）
  ///
  /// 使用 aw-query 语法。常用查询示例：
  /// ```dart
  /// // 按应用名聚合今日窗口时间
  /// client.query(
  ///   timeperiods: ['${today}T00:00:00/${now}'],
  ///   query: ['window = query_bucket("aw-watcher-window_*");',
  ///           'app_events = merge_events_by_keys(window, ["app"]);',
  ///           'RETURN = app_events;'],
  /// );
  /// ```
  Future<List<AWQueryResult>> query({
    required List<String> timeperiods,
    required List<String> query,
  }) async {
    final res = await _dio.post('/query/', data: {
      'timeperiods': timeperiods,
      'query': query,
    });
    final results = res.data as List;
    if (results.isEmpty) return [];
    final periodResult = results[0] as List;
    return periodResult.map((e) => AWQueryResult.fromJson(e)).toList();
  }

  /// 获取最近 N 天的每日总时长
  ///
  /// 一次请求取全部 events，在 Dart 端按本地日期聚合。
  /// 返回的列表按日期升序排列（最早在前），无数据的日期不会出现。
  Future<List<DailyTotal>> getDailyTotals({int days = 7}) async {
    final bucketId = await findWindowBucketId();
    if (bucketId == null) return [];

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));

    final events = await getEvents(
      bucketId,
      limit: 5000,
      start: start,
      end: now,
    );

    // 按日期聚合
    final daily = <DateTime, Duration>{};
    for (final e in events) {
      if (e.duration <= 0) continue;
      final date = DateTime(
        e.timestamp.year,
        e.timestamp.month,
        e.timestamp.day,
      );
      daily.update(
        date,
        (d) => d + Duration(milliseconds: (e.duration * 1000).round()),
        ifAbsent: () =>
            Duration(milliseconds: (e.duration * 1000).round()),
      );
    }

    return daily.entries
        .map((e) => DailyTotal(date: e.key, duration: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 健康检查
  Future<bool> isServerRunning() async {
    try {
      await _dio.get('/info');
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// 单日总时长统计
class DailyTotal {
  final DateTime date;
  final Duration duration;

  const DailyTotal({required this.date, required this.duration});

  /// 总分钟数
  int get totalMinutes => duration.inMinutes;

  /// 简短日期标签（如 "5/26"）
  String get shortLabel =>
      '${date.month}/${date.day}';

  /// 星期标签（如 "周一"）
  String get weekdayLabel => const [
        '周一', '周二', '周三', '周四', '周五', '周六', '周日',
      ][date.weekday - 1];
}
