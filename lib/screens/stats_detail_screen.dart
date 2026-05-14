import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';

const Color _purple = Color(0xFF6C63FF);
const Color _green = Color(0xFF00BFA5);
const Color _orange = Color(0xFFFF7043);

class StatsDetailScreen extends StatefulWidget {
  final String sessionHost;
  const StatsDetailScreen({super.key, required this.sessionHost});

  @override
  StatsDetailScreenState createState() => StatsDetailScreenState();
}

class StatsDetailScreenState extends State<StatsDetailScreen> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _dailyStats = [];
  Map<String, dynamic> _hourlyStats = {};
  List<Map<String, dynamic>> _models = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  int _trendTab = 0; // 0=今日逐小时, 1=7天, 2=30天

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final host = widget.sessionHost;
      final results = await Future.wait([
        http.get(Uri.parse('http://$host/api/stats')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('http://$host/api/stats/daily?days=30')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('http://$host/api/stats/hourly')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('http://$host/api/stats/models')).timeout(const Duration(seconds: 5)),
        http.get(Uri.parse('http://$host/api/sessions?limit=20')).timeout(const Duration(seconds: 5)),
      ]);
      if (results[0].statusCode == 200) _stats = jsonDecode(results[0].body);
      if (results[1].statusCode == 200 && jsonDecode(results[1].body) is List) {
        _dailyStats = (jsonDecode(results[1].body) as List).cast<Map<String, dynamic>>();
      }
      if (results[2].statusCode == 200) _hourlyStats = jsonDecode(results[2].body);
      if (results[3].statusCode == 200 && jsonDecode(results[3].body) is List) {
        _models = (jsonDecode(results[3].body) as List).cast<Map<String, dynamic>>();
      }
      if (results[4].statusCode == 200 && jsonDecode(results[4].body) is List) {
        _sessions = (jsonDecode(results[4].body) as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0, scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF0D0D1A),
        title: const Text('统计详情', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCards(),
                  const SizedBox(height: 20),
                  _buildCacheRate(),
                  const SizedBox(height: 24),
                  _buildTrendSection(),
                  const SizedBox(height: 24),
                  _buildModelSection(),
                  const SizedBox(height: 24),
                  _buildSessionSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ── 总览卡片 ──

  Widget _buildSummaryCards() {
    final total = (_stats['total_input_tokens'] ?? 0) + (_stats['total_output_tokens'] ?? 0)
        + (_stats['total_cache_read'] ?? 0) + (_stats['total_cache_write'] ?? 0);
    final today = (_stats['today_input_tokens'] ?? 0) + (_stats['today_output_tokens'] ?? 0)
        + (_stats['today_cache_read'] ?? 0) + (_stats['today_cache_write'] ?? 0);
    final cache = (_stats['total_cache_read'] ?? 0) + (_stats['total_cache_write'] ?? 0);

    return Row(
      children: [
        Expanded(child: _summaryCard('总消耗', _fmt(total), _purple, Icons.token)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard('今日', _fmt(today), _green, Icons.today)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard('总缓存', _fmt(cache), _orange, Icons.cached)),
      ],
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(100))),
        ],
      ),
    );
  }

  // ── 缓存率进度条 ──

  Widget _buildCacheRate() {
    final inp = _stats['total_input_tokens'] ?? 0;
    final outp = _stats['total_output_tokens'] ?? 0;
    final cache = (_stats['total_cache_read'] ?? 0) + (_stats['total_cache_write'] ?? 0);
    final total = inp + outp + cache;
    final rate = total > 0 ? (cache / total * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('缓存率', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(150))),
              Text('${rate.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _orange)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate / 100,
              backgroundColor: Colors.white.withAlpha(10),
              valueColor: const AlwaysStoppedAnimation<Color>(_orange),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _dotLabel(_purple, '输入 ${_fmt(inp)}'),
              const SizedBox(width: 12),
              _dotLabel(_green, '输出 ${_fmt(outp)}'),
              const SizedBox(width: 12),
              _dotLabel(_orange, '缓存 ${_fmt(cache)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dotLabel(Color c, String t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(100))),
      ],
    );
  }

  // ── 趋势 ──

  Widget _buildTrendSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('消耗趋势', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: Colors.white.withAlpha(200))),
            // Tab 切换
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: ['今日', '7天', '30天'].asMap().entries.map((e) {
                  final i = e.key;
                  final active = _trendTab == i;
                  return GestureDetector(
                    onTap: () => setState(() => _trendTab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? _purple : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(e.value, style: TextStyle(
                          fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                          color: active ? Colors.white : Colors.white.withAlpha(120))),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: _trendTab == 0 ? _buildHourlyChart() : _buildDailyChart(),
        ),
      ],
    );
  }

  // ── 今日逐小时柱状图 ──

  Widget _buildHourlyChart() {
    final List<HourData> data = [];
    for (int h = 0; h < 24; h++) {
      final key = h.toString().padLeft(2, '0');
      final d = _hourlyStats[key] as Map<String, dynamic>?;
      final inp = (d?['input'] ?? 0) as int;
      final outp = (d?['output'] ?? 0) as int;
      final cache = (d?['cache'] ?? 0) as int;
      data.add(HourData(h, inp, outp, cache));
    }
    final maxVal = data.map((d) => d.total).max;
    if (maxVal == 0) return const Center(child: Text('暂无数据', style: TextStyle(color: Colors.white38)));

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal * 1.15,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final d = data[group.x.toInt()];
              return BarTooltipItem(
                '${d.hour}:00\n输入 ${_fmt(d.inp)}\n输出 ${_fmt(d.outp)}\n缓存 ${_fmt(d.cache)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 22,
              getTitlesWidget: (v, _) {
                final h = (v % 24).toInt();
                if (h % 4 != 0) return const SizedBox.shrink();
                return Text('${h}时', style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(80)));
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40,
              getTitlesWidget: (v, _) {
                return Text(_fmt(v.toInt()), style: TextStyle(fontSize: 9, color: Colors.white.withAlpha(60)));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          horizontalInterval: maxVal / 4,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.white.withAlpha(10), strokeWidth: 0.5),
        ),
        barGroups: data.map((d) => BarChartGroupData(
          x: d.hour,
          barRods: [
            BarChartRodData(
              toY: d.total.toDouble(),
              width: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              color: _purple,
            ),
          ],
        )).toList(),
      ),
      duration: const Duration(milliseconds: 200),
    );
  }

  // ── 每日柱状图 ──

  Widget _buildDailyChart() {
    final days = _trendTab == 1 ? 7 : 30;
    var valid = _dailyStats.where((d) => (d['total'] ?? 0) > 0).toList();
    if (_trendTab == 1 && valid.length > 7) {
      valid = valid.length > 7 ? valid.sublist(valid.length - 7) : valid;
    }
    if (valid.isEmpty) return const Center(child: Text('暂无数据', style: TextStyle(color: Colors.white38)));

    final maxVal = valid.fold<int>(0, (m, d) => (d['total'] as int) > m ? d['total'] as int : m);
    if (maxVal == 0) return const SizedBox.shrink();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal * 1.15,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final d = valid[group.x.toInt()];
              return BarTooltipItem(
                '${d['date']}\n输入 ${_fmt(d['input'])}\n输出 ${_fmt(d['output'])}\n缓存 ${_fmt(d['cache'])}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 22,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= valid.length) return const SizedBox.shrink();
                if (valid.length > 10 && i % (valid.length ~/ 5 + 1) != 0) return const SizedBox.shrink();
                return Text(valid[i]['date'] as String,
                    style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(80)));
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40,
              getTitlesWidget: (v, _) {
                return Text(_fmt(v.toInt()), style: TextStyle(fontSize: 9, color: Colors.white.withAlpha(60)));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          horizontalInterval: maxVal / 4,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.white.withAlpha(10), strokeWidth: 0.5),
        ),
        barGroups: valid.asMap().entries.map((e) => BarChartGroupData(
          x: e.key,
          barRods: [
            BarChartRodData(
              toY: (e.value['total'] as num).toDouble(),
              width: _trendTab == 1 ? 28 : 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              color: _purple,
            ),
          ],
        )).toList(),
      ),
      duration: const Duration(milliseconds: 200),
    );
  }

  // ── 模型分布 ──

  Widget _buildModelSection() {
    if (_models.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('模型消耗分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
            color: Colors.white.withAlpha(200))),
        const SizedBox(height: 12),
        ..._models.map((m) {
          final pct = m['pct'] as num;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(m['model'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct.toDouble() / 100,
                      backgroundColor: Colors.white.withAlpha(10),
                      valueColor: const AlwaysStoppedAnimation<Color>(_purple),
                      minHeight: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 50,
                  child: Text('$pct%', textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(150))),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── 会话占比 ──

  Widget _buildSessionSection() {
    if (_sessions.isEmpty) return const SizedBox.shrink();
    final sorted = List<Map<String, dynamic>>.from(_sessions);
    sorted.sort((a, b) {
      final ta = _totalTokens(a);
      final tb = _totalTokens(b);
      return tb.compareTo(ta);
    });
    final grand = sorted.fold<int>(0, (s, item) => s + _totalTokens(item));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('会话消耗排名', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
            color: Colors.white.withAlpha(200))),
        const SizedBox(height: 12),
        ...sorted.map((s) {
          final inp = (s['input_tokens'] ?? 0) as int;
          final outp = (s['output_tokens'] ?? 0) as int;
          final cache = ((s['cache_read_tokens'] ?? 0) as int) + ((s['cache_write_tokens'] ?? 0) as int);
          final total = inp + outp + cache;
          final pct = grand > 0 ? total / grand : 0.0;
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
                        style: const TextStyle(fontSize: 12, color: _purple, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(_purple),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _chip('I', _fmt(inp), _purple),
                    const SizedBox(width: 6),
                    _chip('O', _fmt(outp), _green),
                    const SizedBox(width: 6),
                    _chip('C', _fmt(cache), _orange),
                    const Spacer(),
                    Text(_fmt(total),
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

  int _totalTokens(Map<String, dynamic> s) {
    return ((s['input_tokens'] ?? 0) as int) + ((s['output_tokens'] ?? 0) as int)
        + ((s['cache_read_tokens'] ?? 0) as int) + ((s['cache_write_tokens'] ?? 0) as int);
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(4)),
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

class HourData {
  final int hour, inp, outp, cache;
  int get total => inp + outp + cache;
  HourData(this.hour, this.inp, this.outp, this.cache);
}
