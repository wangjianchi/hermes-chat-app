import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class StatsDetailScreen extends StatefulWidget {
  final String sessionHost;
  const StatsDetailScreen({super.key, required this.sessionHost});

  @override
  StatsDetailScreenState createState() => StatsDetailScreenState();
}

class StatsDetailScreenState extends State<StatsDetailScreen> {
  List<Map<String, dynamic>> _dailyStats = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final host = widget.sessionHost;
      // 每日统计
      final dailyResp = await http.get(
        Uri.parse('http://$host/api/stats/daily?days=30'),
      ).timeout(const Duration(seconds: 5));
      if (dailyResp.statusCode == 200) {
        final data = jsonDecode(dailyResp.body);
        if (data is List) {
          setState(() => _dailyStats = data.cast<Map<String, dynamic>>());
        }
      }
      // 会话列表
      final sessResp = await http.get(
        Uri.parse('http://$host/api/sessions?limit=20'),
      ).timeout(const Duration(seconds: 5));
      if (sessResp.statusCode == 200) {
        final data = jsonDecode(sessResp.body);
        if (data is List) {
          setState(() => _sessions = data.cast<Map<String, dynamic>>());
        }
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildDailyChart(),
                  const SizedBox(height: 28),
                  _buildSessionList(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildDailyChart() {
    final valid = _dailyStats.where((d) => (d['total'] ?? 0) > 0).toList();
    if (valid.isEmpty) {
      return const Center(child: Text('暂无每日数据', style: TextStyle(color: Colors.white38)));
    }
    final maxVal = valid.fold<int>(0, (m, d) => (d['total'] as int) > m ? d['total'] as int : m);
    if (maxVal == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('每日 Token 消耗趋势',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: Colors.white.withAlpha(180))),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: valid.map((d) {
              final total = d['total'] as int;
              final input = d['input'] as int;
              final output = d['output'] as int;
              final cache = d['cache'] as int;
              final ratio = total / maxVal;
              final barH = 140.0 * ratio;
              return Container(
                width: 56,
                margin: const EdgeInsets.only(right: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(_fmt(total),
                        style: const TextStyle(fontSize: 9, color: Colors.white60)),
                    const SizedBox(height: 4),
                    // 堆叠柱状图
                    SizedBox(
                      height: 140,
                      child: CustomPaint(
                        size: const Size(36, 140),
                        painter: _StackedBarPainter(
                          inputRatio: input / maxVal,
                          outputRatio: output / maxVal,
                          cacheRatio: cache / maxVal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(d['date'] as String,
                        style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        // 图例
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(const Color(0xFF6C63FF), '输入'),
            const SizedBox(width: 16),
            _legend(const Color(0xFF00BFA5), '输出'),
            const SizedBox(width: 16),
            _legend(const Color(0xFFFF7043), '缓存'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(
            color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ],
    );
  }

  Widget _buildSessionList() {
    if (_sessions.isEmpty) {
      return const Center(child: Text('暂无会话', style: TextStyle(color: Colors.white38)));
    }

    // 计算总 token（含缓存）并排序
    final sorted = List<Map<String, dynamic>>.from(_sessions);
    sorted.sort((a, b) {
      final ta = ((a['input_tokens'] ?? 0) as int) + ((a['output_tokens'] ?? 0) as int)
          + ((a['cache_read_tokens'] ?? 0) as int) + ((a['cache_write_tokens'] ?? 0) as int);
      final tb = ((b['input_tokens'] ?? 0) as int) + ((b['output_tokens'] ?? 0) as int)
          + ((b['cache_read_tokens'] ?? 0) as int) + ((b['cache_write_tokens'] ?? 0) as int);
      return tb.compareTo(ta);
    });

    final grandTotal = sorted.fold<int>(0, (int s, item) {
      final inp = (item['input_tokens'] ?? 0) as int;
      final outp = (item['output_tokens'] ?? 0) as int;
      final cache = ((item['cache_read_tokens'] ?? 0) as int) + ((item['cache_write_tokens'] ?? 0) as int);
      return s + inp + outp + cache;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('会话消耗占比',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: Colors.white.withAlpha(180))),
        const SizedBox(height: 12),
        ...sorted.map((s) {
          final inp = s['input_tokens'] ?? 0;
          final outp = s['output_tokens'] ?? 0;
          final cache = (s['cache_read_tokens'] ?? 0) + (s['cache_write_tokens'] ?? 0);
          final total = inp + outp + cache;
          final pct = grandTotal > 0 ? total / grandTotal : 0.0;
          final title = s['title'] as String? ?? s['id'] as String;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                    Text('${(pct * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6C63FF),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                // 占比条
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _chip('I', _fmt(inp), const Color(0xFF6C63FF)),
                    const SizedBox(width: 6),
                    _chip('O', _fmt(outp), const Color(0xFF00BFA5)),
                    const SizedBox(width: 6),
                    _chip('C', _fmt(cache), const Color(0xFFFF7043)),
                    const Spacer(),
                    Text('${_fmt(total)}',
                        style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(100))),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label $value',
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  String _fmt(dynamic val) {
    final n = (val is num) ? val.toInt() : int.tryParse(val.toString()) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _StackedBarPainter extends CustomPainter {
  final double inputRatio;
  final double outputRatio;
  final double cacheRatio;

  _StackedBarPainter({
    required this.inputRatio,
    required this.outputRatio,
    required this.cacheRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width;
    final barH = size.height;
    final r = 4.0;

    // totalR = 该日总量 / 最大值，决定柱子总高度
    final totalR = inputRatio + outputRatio + cacheRatio;
    if (totalR <= 0) return;

    final actualH = (barH * totalR).clamp(0, barH);
    double y = barH; // 从底部往上画

    // 缓存（橙色）— 底部
    if (cacheRatio > 0 && totalR > 0) {
      final h = actualH * cacheRatio / totalR;
      y -= h;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(0, y, barW, h),
            bottomLeft: Radius.circular(r), bottomRight: Radius.circular(r)),
        Paint()..color = const Color(0xFFFF7043));
    }
    // 输出（绿色）— 中间
    if (outputRatio > 0 && totalR > 0) {
      final h = actualH * outputRatio / totalR;
      y -= h;
      canvas.drawRect(Rect.fromLTWH(0, y, barW, h), Paint()..color = const Color(0xFF00BFA5));
    }
    // 输入（紫色）— 顶部
    if (inputRatio > 0 && totalR > 0) {
      final h = actualH * inputRatio / totalR;
      y -= h;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(0, y, barW, h),
            topLeft: Radius.circular(r), topRight: Radius.circular(r)),
        Paint()..color = const Color(0xFF6C63FF));
    }
  }

  @override
  bool shouldRepaint(covariant _StackedBarPainter old) =>
      old.inputRatio != inputRatio || old.outputRatio != outputRatio || old.cacheRatio != cacheRatio;
}
