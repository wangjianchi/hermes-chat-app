import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/hermes_api.dart';
import 'settings_screen.dart';
import 'stats_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  final HermesApiService apiService;
  final Function(bool) onConnected;

  const ProfileScreen({
    super.key,
    required this.apiService,
    required this.onConnected,
  });

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void refresh() {
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final host = kIsWeb ? 'localhost:8080' : '100.126.192.84:8080';
      // 加载统计
      final statsResp = await http.get(
        Uri.parse('http://$host/api/stats'),
      ).timeout(const Duration(seconds: 5));
      if (statsResp.statusCode == 200) {
        setState(() => _stats = jsonDecode(statsResp.body));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openStatsDetail() async {
    final host = kIsWeb ? 'localhost:8080' : '100.126.192.84:8080';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatsDetailScreen(sessionHost: host),
      ),
    );
  }

  String _formatNumber(dynamic val) {
    if (val == null) return '0';
    final n = (val is num) ? val.toInt() : int.tryParse(val.toString()) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  String _formatTokens(dynamic val) {
    if (val == null) return '0';
    final n = (val is num) ? val.toInt() : int.tryParse(val.toString()) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    apiService: widget.apiService,
                    onConnected: widget.onConnected,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 64, color: Colors.white.withAlpha(60)),
              const SizedBox(height: 16),
              Text('无法加载统计数据',
                  style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 18)),
              const SizedBox(height: 8),
              Text('请确保后端服务器已启动',
                  style: TextStyle(color: Colors.white.withAlpha(60), fontSize: 13)),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final s = _stats;
    final todaySessions = s['today_sessions'] ?? 0;
    final todayTokens = (s['today_input_tokens'] ?? 0) + (s['today_output_tokens'] ?? 0)
        + (s['today_cache_read'] ?? 0) + (s['today_cache_write'] ?? 0);
    final todayOutput = s['today_output_tokens'] ?? 0;
    final todayCache = (s['today_cache_read'] ?? 0) + (s['today_cache_write'] ?? 0);
    final totalTokens = (s['total_input_tokens'] ?? 0) + (s['total_output_tokens'] ?? 0)
        + (s['total_cache_read'] ?? 0) + (s['total_cache_write'] ?? 0);
    final todayCacheRate = todayTokens > 0
        ? (todayCache / todayTokens * 100).toStringAsFixed(1)
        : '0.0';

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 头部头像区域
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFF6C63FF),
                  child: const Icon(Icons.person, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Hermes 聊天',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'v1.0.0+2',
                  style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(100)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 今日统计卡片
          GestureDetector(
            onTap: () => _openStatsDetail(),
            child: Text('今日统计',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    color: Colors.white.withAlpha(180))),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCard(
                Icons.chat_bubble_outline, '会话',
                _formatNumber(todaySessions), const Color(0xFF6C63FF))),
              const SizedBox(width: 12),
              Expanded(child: _statCard(
                Icons.token_outlined, '总Token',
                _formatTokens(todayTokens), const Color(0xFF00BFA5),
                onTap: () => _openStatsDetail())),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCard(
                Icons.output_outlined, '总输出',
                _formatTokens(todayOutput), const Color(0xFF42A5F5))),
              const SizedBox(width: 12),
              Expanded(child: _statCard(
                Icons.cached_outlined, '缓存率',
                '$todayCacheRate%', const Color(0xFFFF7043))),
            ],
          ),
          const SizedBox(height: 28),

          // 全部统计
          Text('全部累计',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                  color: Colors.white.withAlpha(180))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _infoRow('总会话数', _formatNumber(s['total_sessions'])),
                _infoRow('总输入 Token', _formatTokens(s['total_input_tokens'])),
                _infoRow('总输出 Token', _formatTokens(s['total_output_tokens'])),
                _infoRow('总缓存读取', _formatTokens(s['total_cache_read'])),
                _infoRow('总缓存写入', _formatTokens(s['total_cache_write'])),
                const Divider(height: 24, color: Color(0xFF2A2A3E)),
                _infoRow('总消耗 Token', _formatTokens(totalTokens)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 设置按钮
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    apiService: widget.apiService,
                    onConnected: widget.onConnected,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('打开设置'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color, {VoidCallback? onTap}) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(150))),
          Text(value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
