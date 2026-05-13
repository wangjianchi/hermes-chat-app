import 'package:flutter/material.dart';
import '../services/hermes_api.dart';

class HistoryScreen extends StatefulWidget {
  final HermesApiService apiService;
  final void Function(String sessionId, List<Map<String, dynamic>> messages) onSessionTap;

  const HistoryScreen({
    super.key,
    required this.apiService,
    required this.onSessionTap,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sessions = await widget.apiService.fetchSessions();
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _preview(Map<String, dynamic> s) {
    // 优先用 title，但去掉 JSON/thinking 痕迹
    String text = '';
    final rawTitle = s['title'] as String?;
    final rawPreview = s['preview'] as String?;
    if (rawTitle != null && rawTitle.trim().isNotEmpty) {
      text = rawTitle;
    } else if (rawPreview != null && rawPreview.trim().isNotEmpty) {
      text = rawPreview;
    } else {
      return '(空)';
    }
    // 去掉 JSON 结构、thinking 标记、工具调用
    text = text.replaceAll(RegExp(r'\{[^}]*\}'), '');
    text = text.replaceAll(RegExp(r'<thinking>[^<]*</thinking>'), '');
    text = text.replaceAll(RegExp(r'```[a-z]*\n[\s\S]*?\n```'), '');
    text = text.replaceAll(RegExp(r'"[^"]*"\s*:\s*'), '');
    text = text.trim();
    if (text.isEmpty) text = '(空)';
    // 最多 2 行
    final lines = text.split('\n');
    if (lines.length > 2) {
      text = '${lines[0]}\n${lines[1]}';
    }
    return text;
  }

  String _timeAgo(Map<String, dynamic> s) {
    DateTime? dt;
    final lastActive = s['last_active'];
    if (lastActive is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(lastActive * 1000);
    } else if (lastActive is double) {
      dt = DateTime.fromMillisecondsSinceEpoch((lastActive * 1000).toInt());
    } else if (lastActive is String) {
      try {
        dt = DateTime.parse(lastActive);
      } catch (_) {}
    }
    final ts = s['started_at'];
    if (dt == null && ts is String) {
      try {
        dt = DateTime.parse(ts);
      } catch (_) {}
    }
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  IconData _icon(Map<String, dynamic> s) {
    final source = (s['source'] as String? ?? '');
    if (source == 'api_server') return Icons.api;
    if (source == 'cli') return Icons.terminal;
    if (source == 'telegram') return Icons.telegram;
    if (source == 'discord') return Icons.headset_mic;
    return Icons.chat_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史会话'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
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
              Text('无法加载历史会话',
                  style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 18)),
              const SizedBox(height: 8),
              Text('请确保后端服务器已启动:\ncd chat_app && python3 server.py',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withAlpha(60), fontSize: 13)),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.white.withAlpha(40)),
            const SizedBox(height: 16),
            Text('暂无会话记录',
                style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 18)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
        itemBuilder: (context, index) {
          final s = _sessions[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF6C63FF).withAlpha(60),
              child: Icon(_icon(s), size: 20, color: const Color(0xFF6C63FF)),
            ),
            title: Text(
              _preview(s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${_timeAgo(s)}  · ${(s['source'] as String? ?? '') == 'api_server' ? 'API' : (s['source'] as String? ?? '未知')}',
              style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(80)),
            ),
            onTap: () async {
              final sid = s['id'] as String?;
              if (sid == null) return;
              // 显示加载中
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              );
              final msgs = await widget.apiService.fetchSessionMessages(sid, limit: 30);
              if (context.mounted) Navigator.of(context).pop();
              widget.onSessionTap(sid, msgs);
            },
          );
        },
      ),
    );
  }
}
