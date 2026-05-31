/// 主面板 — 时光镜 Dashboard
///
/// 设计要点：
/// - 暗色数据面板风格，三档阈值颜色指示
/// - 窗口重新获得焦点时自动刷新（不做定时轮询）
/// - 连接状态横幅、今日摘要卡片、应用排行列表
/// - 四种状态：加载中 / 断开 / 无数据 / 已加载
/// - 自动过滤 TimeLens 自身，不污染排行数据
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/api_client.dart';
import '../../core/threshold_config.dart';

/// 连接状态
enum _ConnectionStatus { connected, disconnected, checking }

/// 应用使用统计
class AppUsage {
  final String appName;
  final Duration todayTotal;

  const AppUsage({required this.appName, required this.todayTotal});

  /// 是否匹配 TimeLens 自身（避免污染排行）
  static bool isSelf(String appName) {
    final lower = appName.toLowerCase();
    return lower.contains('timelens') ||
        lower.contains('flutter') && lower.contains('时光镜');
  }
}

/// Dashboard 页面
///
/// [initialServerRunning] 用于初始 UI 状态：当已知服务器未运行时，
/// 直接显示"未连接"状态，避免先闪烁"加载中"再切换到断开状态。
class DashboardPage extends StatefulWidget {
  final AWClient client;
  final VoidCallback? onToggleMini;

  /// 初始服务器连接状态（由 main.dart 在启动时检测）
  final bool initialServerRunning;

  /// 阈值配置列表（可读写）
  final List<AppThresholdConfig> thresholdConfigs;

  /// 配置变更回调 → 持久化 + 通知 TimerService
  final ValueChanged<List<AppThresholdConfig>>? onConfigsChanged;

  const DashboardPage({
    super.key,
    required this.client,
    this.onToggleMini,
    this.initialServerRunning = true,
    required this.thresholdConfigs,
    this.onConfigsChanged,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WindowListener {
  // ── 数据状态 ──────────────────────────────────────
  List<AppUsage> _apps = [];
  _ConnectionStatus _connectionStatus = _ConnectionStatus.checking;
  DateTime? _lastUpdated;
  bool _loading = true;

  // ── 阈值配置 ──────────────────────────────────────
  // 使用父组件传入的配置（支持运行时修改 + 持久化）
  late List<AppThresholdConfig> _thresholdConfigs;

  // ── 设置面板 ──────────────────────────────────────
  bool _showThresholdPanel = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
    }
    _thresholdConfigs = widget.thresholdConfigs;

    // 已知服务器未运行 → 直接显示断开状态，不闪"加载中"
    if (!widget.initialServerRunning) {
      _loading = false;
      _connectionStatus = _ConnectionStatus.disconnected;
    }

    _loadData();
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  // ── WindowListener：焦点恢复时自动刷新 ────────────

  @override
  void onWindowFocus() => _loadData();

  @override
  void onWindowClose() {}
  @override
  void onWindowMaximize() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowRestore() {}
  @override
  void onWindowResize() {}
  @override
  void onWindowMove() {}
  @override
  void onWindowEnterFullScreen() {}
  @override
  void onWindowLeaveFullScreen() {}

  // ── 数据加载 ──────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _loading = _apps.isEmpty;
      _connectionStatus = _ConnectionStatus.checking;
    });

    try {
      final connected = await widget.client.isServerRunning();
      if (!connected) {
        setState(() {
          _loading = false;
          _connectionStatus = _ConnectionStatus.disconnected;
        });
        return;
      }

      final bucketId = await widget.client.findWindowBucketId();
      if (bucketId == null) {
        setState(() {
          _loading = false;
          _connectionStatus = _ConnectionStatus.connected;
          _apps = [];
        });
        return;
      }

      final events = await widget.client.getTodayEvents(bucketId);

      // 按应用名聚合时长，排除时间回溯事件
      final usage = <String, Duration>{};
      for (final e in events) {
        if (e.duration <= 0) continue; // 跳过异常负时长
        usage.update(
          e.app,
          (d) => d + Duration(milliseconds: (e.duration * 1000).round()),
          ifAbsent: () =>
              Duration(milliseconds: (e.duration * 1000).round()),
        );
      }

      _apps = usage.entries
          .where((e) => !AppUsage.isSelf(e.key)) // 过滤 TimeLens 自身
          .map((e) => AppUsage(appName: e.key, todayTotal: e.value))
          .toList()
        ..sort((a, b) => b.todayTotal.compareTo(a.todayTotal));

      setState(() {
        _loading = false;
        _connectionStatus = _ConnectionStatus.connected;
        _lastUpdated = DateTime.now();
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _connectionStatus = _ConnectionStatus.disconnected;
      });
    }
  }

  // ── 构建 ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 连接状态横幅
          if (_connectionStatus == _ConnectionStatus.disconnected)
            _buildConnectionBanner(),

          // 主体内容
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// AppBar：标题 + 手动刷新
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Row(
        children: [
          Icon(Icons.hourglass_bottom, size: 20, color: Colors.white70),
          SizedBox(width: 8),
          Text(
            '时光镜',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF16213E),
      elevation: 0,
      centerTitle: false,
      actions: [
        if (_lastUpdated != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                _formatTimeAgo(_lastUpdated!),
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: '刷新',
          onPressed: _loadData,
        ),
      ],
    );
  }

  /// 连接状态横幅
  Widget _buildConnectionBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF3E2723), // 琥珀色背景
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Color(0xFFFFB74D), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ActivityWatch 未连接',
                  style: TextStyle(
                    color: Color(0xFFFFB74D),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '请确保 aw-server 正在运行 (localhost:5600)',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _loadData,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFB74D),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('重试', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 主体内容（按状态分支）
  Widget _buildBody() {
    // 加载中
    if (_loading && _apps.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF0F3460),
              ),
            ),
            SizedBox(height: 16),
            Text(
              '加载中...',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // 无数据
    if (_apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty,
                color: Colors.white.withValues(alpha: 0.15), size: 48),
            const SizedBox(height: 16),
            const Text(
              '今日暂无屏幕使用记录',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              '开始使用电脑后数据将自动出现',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // 已加载有数据：摘要卡片 + 排行列表
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF0F3460),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 20),
          _buildSectionHeader(),
          const SizedBox(height: 10),
          ..._apps.map(_buildAppTile),
          const SizedBox(height: 16),
          _buildThresholdPanel(),
        ],
      ),
    );
  }

  // ── 摘要卡片 ──────────────────────────────────────

  /// 今日摘要卡片：总计时长 + 应用数
  Widget _buildSummaryCard() {
    final total = _apps.fold<Duration>(
      Duration.zero,
      (sum, app) => sum + app.todayTotal,
    );
    final totalConfig = AppThresholdConfig.find(_thresholdConfigs, '*');
    final totalColor = totalConfig.textColorFor(total);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F3460), Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F3460).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 总计时长 — 大字
          Text(
            _formatDurationLong(total),
            style: TextStyle(
              color: totalColor,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          // 分隔线
          Container(
            width: 32,
            height: 2,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 10),
          // 应用数
          Row(
            children: [
              const Icon(Icons.apps, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Text(
                '${_apps.length} 个应用',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (_lastUpdated != null)
                Text(
                  '更新于 ${_formatTimeAgo(_lastUpdated!)}',
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 分区标题：应用排行
  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF0F3460),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '应用排行',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── 应用排行条目 ──────────────────────────────────

  /// 单个应用排行条目
  ///
  /// 布局：序号圈 → 应用名+进度条 → 时长
  /// 进度条满格基准 60 分钟
  /// 时长颜色根据阈值配置动态计算
  Widget _buildAppTile(AppUsage app) {
    final config = AppThresholdConfig.find(_thresholdConfigs, app.appName);
    final threshold = config.thresholdFor(app.todayTotal);
    final accentColor = config.textColorFor(app.todayTotal);
    final totalMinutes = app.todayTotal.inMinutes;
    // 进度条基准 60 分钟
    final progress = (totalMinutes / 60).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(8),
        // 超阈值应用左侧红色描边
        border: threshold != TimerThreshold.green
            ? Border(left: BorderSide(color: accentColor, width: 3))
            : null,
      ),
      child: Row(
        children: [
          // 序号圆圈
          _buildRankCircle(_apps.indexOf(app) + 1, accentColor, threshold),

          const SizedBox(width: 12),

          // 应用名 + 进度条
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: const Color(0xFF1A1A2E),
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // 时长（等宽字体 + 阈值颜色）
          Text(
            _formatDuration(app.todayTotal),
            style: TextStyle(
              color: accentColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 排行序号圆圈
  Widget _buildRankCircle(int rank, Color color, TimerThreshold threshold) {
    final isTop3 = rank <= 3;
    final bgColor = isTop3
        ? color.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.06);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          color: isTop3 ? color : Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  // ── 格式化工具 ────────────────────────────────────

  /// 长格式时间：h 小时 m 分钟 / m 分钟 / <1 分钟
  String _formatDurationLong(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) {
      return '$h\x68 $m\x6D';
    }
    if (m > 0) {
      return '$m 分钟';
    }
    return '<1 分钟';
  }

  /// 短格式时间：用于排行列表
  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) {
      return '$h\x68 $m\x6D';
    }
    if (m > 0) {
      return '$m\x6D';
    }
    return '${d.inSeconds}s';
  }

  /// 相对时间："12秒前" / "3分钟前"
  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 10) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    return '${diff.inHours}小时前';
  }

  // ══════════════════════════════════════════════════
  // 应用阈值设置面板
  // ══════════════════════════════════════════════════

  Widget _buildThresholdPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // ── 面板标题（可折叠） ──
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () => setState(() => _showThresholdPanel = !_showThresholdPanel),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: Colors.white54, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    '应用阈值',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showThresholdPanel
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white30,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── 展开内容 ──
          if (_showThresholdPanel) ...[
            const Divider(height: 1, color: Color(0xFF1A1A2E)),
            // 应用列表
            ..._apps.map((app) => _buildThresholdRow(app)),
            // 底部操作
            const Divider(height: 1, color: Color(0xFF1A1A2E)),
            InkWell(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(10)),
              onTap: () => _showAddRuleDialog(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline,
                        color: Colors.white.withValues(alpha: 0.4), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '添加规则',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 单个应用的阈值行
  Widget _buildThresholdRow(AppUsage app) {
    final config = AppThresholdConfig.find(_thresholdConfigs, app.appName);
    final isCustom =
        config.appPattern != '*' && config.matches(app.appName);
    final steps = config.steps;

    // 阈值摘要文本
    String summary;
    if (steps.length >= 3) {
      final g = steps[0].maxDuration.inMinutes;
      final y = steps[1].maxDuration.inMinutes;
      summary = '绿≤$g 黄≤$y 红>$y';
    } else {
      summary = '默认规则';
    }

    return InkWell(
      onTap: () => _showEditDialog(app.appName, config),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // 应用名
            Expanded(
              child: Text(
                app.appName,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // 阈值摘要 + 颜色预览
            _buildColorPreview(steps),
            const SizedBox(width: 6),
            Text(
              summary,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 6),
            // 操作图标
            Icon(
              isCustom ? Icons.edit : Icons.add_circle_outline,
              color: isCustom
                  ? Colors.white.withValues(alpha: 0.4)
                  : const Color(0xFF66BB6A).withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  /// 颜色预览（三个色块）
  Widget _buildColorPreview(List<ThresholdStep> steps) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: steps.take(3).map((s) {
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: s.textColor,
            shape: BoxShape.circle,
          ),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════════════
  // 阈值编辑对话框
  // ══════════════════════════════════════════════════

  /// 编辑应用阈值（弹窗）
  void _showEditDialog(String appName, AppThresholdConfig currentConfig) {
    final steps = currentConfig.steps.map((s) => s).toList();
    // 取前两个阶梯的分钟数作为可编辑值
    int greenToYellow = steps.isNotEmpty
        ? steps[0].maxDuration.inMinutes
        : 30;
    int yellowToRed = steps.length >= 2
        ? steps[1].maxDuration.inMinutes
        : 60;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Row(
                children: [
                  const Icon(Icons.tune, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    appName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white30, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              titlePadding:
                  const EdgeInsets.fromLTRB(20, 18, 12, 0),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 绿→黄 阈值 ──
                    _buildSliderRow(
                      label: '绿 → 黄',
                      color: steps[0].textColor,
                      value: greenToYellow,
                      max: 180,
                      onChanged: (v) => setDialogState(() => greenToYellow = v),
                    ),
                    const SizedBox(height: 16),
                    // ── 黄→红 阈值 ──
                    _buildSliderRow(
                      label: '黄 → 红',
                      color: steps.length >= 2
                          ? steps[1].textColor
                          : const Color(0xFFF9A825),
                      value: yellowToRed,
                      max: 480,
                      onChanged: (v) => setDialogState(() => yellowToRed = v),
                    ),
                    const SizedBox(height: 20),
                    // ── 颜色预览 ──
                    Text(
                      '预览:  00:${greenToYellow.toString().padLeft(2, '0')}  '
                      '${yellowToRed.toString().padLeft(2, '0')}:00  '
                      '${(yellowToRed + 1).toString().padLeft(2, '0')}:00',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Row(
                      children: [
                        _buildPreviewBlock(steps[0].textColor, '$greenToYellow min', greenToYellow),
                        _buildPreviewBlock(
                          steps.length >= 2
                              ? steps[1].textColor
                              : const Color(0xFFF9A825),
                          '${yellowToRed - greenToYellow} min',
                          yellowToRed - greenToYellow,
                        ),
                        _buildPreviewBlock(
                          steps.length >= 3
                              ? steps[2].textColor
                              : const Color(0xFFEF5350),
                          '>$yellowToRed min',
                          0,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── 按钮 ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 恢复默认
                        TextButton(
                          onPressed: () {
                            _removeCustomRule(appName);
                            Navigator.of(ctx).pop();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white38,
                          ),
                          child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                        ),
                        // 保存
                        FilledButton(
                          onPressed: () {
                            _saveCustomRule(
                              appName,
                              greenToYellow,
                              yellowToRed,
                            );
                            Navigator.of(ctx).pop();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F3460),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('保存', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 滑块行
  Widget _buildSliderRow({
    required String label,
    required Color color,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$value 分钟',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            activeTrackColor: color,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 5,
            max: max.toDouble(),
            divisions: max ~/ 5,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }

  /// 颜色预览块
  Widget _buildPreviewBlock(Color color, String label, int width) {
    return Expanded(
      child: Container(
        height: 28,
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// 保存自定义规则
  void _saveCustomRule(String appName, int greenToYellow, int yellowToRed) {
    // 移除该应用的现有自定义规则
    _thresholdConfigs.removeWhere(
      (c) => c.appPattern != '*' && c.matches(appName),
    );

    // 添加新规则
    final defaultSteps = AppThresholdConfig.defaultRule.steps;
    _thresholdConfigs.add(AppThresholdConfig(
      appPattern: appName,
      steps: [
        ThresholdStep(
          maxDuration: Duration(minutes: greenToYellow),
          textColor: defaultSteps[0].textColor,
        ),
        ThresholdStep(
          maxDuration: Duration(minutes: yellowToRed),
          textColor: defaultSteps[1].textColor,
        ),
        ThresholdStep(
          maxDuration: ThresholdStep.infinity,
          textColor: defaultSteps[2].textColor,
        ),
      ],
    ));

    // 确保默认规则在末尾
    _ensureDefaultLast();
    _notifyConfigChanged();
  }

  /// 移除自定义规则（恢复默认）
  void _removeCustomRule(String appName) {
    _thresholdConfigs.removeWhere(
      (c) => c.appPattern != '*' && c.matches(appName),
    );
    _notifyConfigChanged();
  }

  /// 添加规则对话框 — 从今日应用列表中选择
  void _showAddRuleDialog() {
    // 过滤出尚未有自定义规则的应用
    final customApps = _thresholdConfigs
        .where((c) => c.appPattern != '*')
        .map((c) => c.appPattern.toLowerCase())
        .toSet();
    final uncustomizedApps =
        _apps.where((a) => !customApps.contains(a.appName.toLowerCase()));

    if (uncustomizedApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('今日所有应用已有自定义规则'),
          backgroundColor: Color(0xFF16213E),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            '选择应用',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: uncustomizedApps.take(8).map((app) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    app.appName,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  trailing: const Icon(Icons.add, color: Colors.white30, size: 18),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final defaultConfig =
                        AppThresholdConfig.find(_thresholdConfigs, app.appName);
                    _showEditDialog(app.appName, defaultConfig);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  /// 确保默认规则（'*'）在列表末尾
  void _ensureDefaultLast() {
    final defaultIdx =
        _thresholdConfigs.indexWhere((c) => c.appPattern == '*');
    if (defaultIdx >= 0 && defaultIdx != _thresholdConfigs.length - 1) {
      final defaultConfig = _thresholdConfigs.removeAt(defaultIdx);
      _thresholdConfigs.add(defaultConfig);
    }
  }

  /// 通知父组件配置变更 → 持久化 + 更新 TimerService
  void _notifyConfigChanged() {
    setState(() {}); // 刷新阈值颜色
    widget.onConfigsChanged?.call(List.of(_thresholdConfigs));
  }
}
