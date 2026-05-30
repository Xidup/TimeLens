/// 主面板 — 时光镜 Dashboard
///
/// 显示今日应用使用统计、排行榜、和悬浮窗控制。
/// Windows 端使用 Fluent UI，Android 端使用 Material Design。
library;

import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/timer_service.dart';
import '../overlay/overlay_window.dart';

/// Dashboard 页面
class DashboardPage extends StatefulWidget {
  final AWClient client;
  final TimerService timerService;
  final VoidCallback? onToggleMini;

  const DashboardPage({
    super.key,
    required this.client,
    required this.timerService,
    this.onToggleMini,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<AppUsage> _apps = [];
  bool _loading = true;
  bool _overlayActive = false;

  @override
  void initState() {
    super.initState();
    widget.timerService.onStateChanged = (_) {
      if (mounted) setState(() {});
    };
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final bucketId = await widget.client.findWindowBucketId();
      if (bucketId != null) {
        final events = await widget.client.getTodayEvents(bucketId);
        final usage = <String, Duration>{};
        for (final e in events) {
          usage.update(
            e.app,
            (d) => d + Duration(milliseconds: (e.duration * 1000).round()),
            ifAbsent: () =>
                Duration(milliseconds: (e.duration * 1000).round()),
          );
        }
        _apps = usage.entries
            .map((e) => AppUsage(appName: e.key, todayTotal: e.value))
            .toList()
          ..sort((a, b) => b.todayTotal.compareTo(a.todayTotal));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.timerService.state;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hourglass_bottom, size: 22),
            SizedBox(width: 8),
            Text('时光镜', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: const Color(0xFF16213E),
        actions: [
          if (widget.onToggleMini != null)
            IconButton(
              icon: const Icon(Icons.picture_in_picture),
              tooltip: '迷你悬浮窗',
              onPressed: widget.onToggleMini,
            ),
          IconButton(
            icon: Icon(
              _overlayActive ? Icons.visibility_off : Icons.visibility,
            ),
            tooltip: _overlayActive ? '隐藏悬浮窗' : '显示悬浮窗',
            onPressed: () => setState(() => _overlayActive = !_overlayActive),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // 当前计时预览
          if (_overlayActive)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF0F3460),
              child: Column(
                children: [
                  const Text(
                    '悬浮窗预览',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  OverlayWindow(state: state),
                ],
              ),
            ),

          // 今日总计
          _buildTodaySummary(),

          // 应用列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _apps.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无数据\n请确保 ActivityWatch 正在运行',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _apps.length,
                        itemBuilder: (context, index) =>
                            _buildAppTile(_apps[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySummary() {
    final state = widget.timerService.state;
    final total = _apps.fold<Duration>(
      Duration.zero,
      (sum, app) => sum + app.todayTotal,
    );

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3460), Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('今日总计', _formatDuration(total), Icons.timer),
          _summaryItem('应用数', '${_apps.length}', Icons.apps),
          _summaryItem(
            '当前',
            state.appName.isEmpty ? '--' : state.appName,
            Icons.play_arrow,
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildAppTile(AppUsage app) {
    final totalMinutes = app.todayTotal.inMinutes;
    final isOverThreshold = totalMinutes >= 30;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(8),
        border: isOverThreshold
            ? Border.all(color: const Color(0xFFC62828), width: 1)
            : null,
      ),
      child: Row(
        children: [
          Icon(
            isOverThreshold ? Icons.warning_amber : Icons.check_circle_outline,
            color: isOverThreshold
                ? const Color(0xFFEF5350)
                : const Color(0xFF66BB6A),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: (totalMinutes / 60).clamp(0.0, 1.0),
                  backgroundColor: const Color(0xFF1A1A2E),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isOverThreshold
                        ? const Color(0xFFEF5350)
                        : const Color(0xFF66BB6A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatDuration(app.todayTotal),
            style: TextStyle(
              color: isOverThreshold
                  ? const Color(0xFFEF5350)
                  : Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}min';
  }
}
