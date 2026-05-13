import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import '../models/chat_message.dart';
import '../services/hermes_api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final HermesApiService _apiService = HermesApiService();
  bool _isConnected = false;

  // 用于从历史会话跳转到聊天
  String? _resumeSessionId;
  List<ChatMessage>? _resumeMessages;
  int _resumeKey = 0;

  // 自动恢复上次会话的标志
  bool _autoResumed = false;
  GlobalKey<ProfileScreenState> _profileKey = GlobalKey<ProfileScreenState>();

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _autoResumeLastSession();
  }

  Future<void> _checkConnection() async {
    final ok = await _apiService.checkHealth();
    setState(() => _isConnected = ok);
  }

  /// 启动时自动恢复上次关闭时的最后一个会话
  Future<void> _autoResumeLastSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSessionId = prefs.getString('last_session_id');

      // 获取最近会话列表
      final sessions = await _apiService.fetchSessions(limit: 1);
      if (sessions.isEmpty) return;

      final mostRecent = sessions.first;
      final recentId = mostRecent['id'] as String?;
      if (recentId == null) return;

      // 如果 savedSessionId 存在且匹配最近的会话，就用它
      // 否则使用最近会话
      String targetId;
      if (savedSessionId != null) {
        // 找到 savedSessionId 对应的会话
        final allSessions = await _apiService.fetchSessions(limit: 50);
        final match = allSessions.where(
            (s) => s['id'] == savedSessionId).toList();
        if (match.isNotEmpty) {
          targetId = savedSessionId;
        } else {
          targetId = recentId;
        }
      } else {
        targetId = recentId;
      }

      // 加载该会话消息
      final msgs = await _apiService.fetchSessionMessages(targetId, limit: 30);
      if (msgs.isEmpty) return;

      final chatMessages = msgs
          .where((m) =>
              m['role'] != 'tool' &&
              m['content'] is String &&
              (m['content'] as String).isNotEmpty)
          .map((m) => ChatMessage(
                id: 'hist-${m.hashCode}',
                content: m['content'] as String,
                isUser: m['role'] == 'user',
                timestamp: DateTime.now(),
                reasoning: m['reasoning'] as String?,
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _resumeSessionId = targetId;
        _resumeMessages = chatMessages;
        _resumeKey++;
        _autoResumed = true;
      });
    } catch (_) {
      // 静默失败，显示空会话
    }
  }

  void _onSessionTap(String sessionId, List<Map<String, dynamic>> rawMessages) {
    final msgs = rawMessages
        .where((m) =>
            m['role'] != 'tool' &&
            m['content'] is String &&
            (m['content'] as String).isNotEmpty)
        .map((m) => ChatMessage(
              id: 'hist-${m.hashCode}',
              content: m['content'] as String,
              isUser: m['role'] == 'user',
              timestamp: DateTime.now(),
              reasoning: m['reasoning'] as String?,
            ))
        .toList();

    setState(() {
      _resumeSessionId = sessionId;
      _resumeMessages = msgs;
      _resumeKey++;
      _currentIndex = 0;
    });

    // 保存到 SharedPreferences
    _saveLastSessionId(sessionId);
  }

  Future<void> _saveLastSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_session_id', sessionId);
  }

  void _onChatUpdated(String? sessionId) {
    if (sessionId != null) {
      _saveLastSessionId(sessionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ChatScreen(
            key: ValueKey('chat_$_resumeKey'),
            apiService: _apiService,
            initialSessionId: _resumeSessionId,
            initialMessages: _resumeMessages,
            onSessionChanged: _onChatUpdated,
          ),
          HistoryScreen(
            apiService: _apiService,
            onSessionTap: _onSessionTap,
          ),
          ProfileScreen(
            key: _profileKey,
            apiService: _apiService,
            onConnected: (connected) {
              setState(() => _isConnected = connected);
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          // 切换到"我的"时刷新统计
          if (i == 2) {
            _profileKey.currentState?.refresh();
          }
        },
        indicatorColor: const Color(0xFF6C63FF).withAlpha(60),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: Color(0xFF6C63FF)),
            label: '聊天',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: Color(0xFF6C63FF)),
            label: '历史',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: !_isConnected,
              child: const Icon(Icons.person_outline),
            ),
            selectedIcon: const Icon(Icons.person, color: Color(0xFF6C63FF)),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
