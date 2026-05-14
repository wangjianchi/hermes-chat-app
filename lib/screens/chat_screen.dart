import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/hermes_api.dart';

class ChatScreen extends StatefulWidget {
  final HermesApiService apiService;
  final String? initialSessionId;
  final List<ChatMessage>? initialMessages;
  final String? initialSessionTitle;
  final int initialOffset;
  final void Function(String? sessionId)? onSessionChanged;

  const ChatScreen({
    super.key,
    required this.apiService,
    this.initialSessionId,
    this.initialMessages,
    this.initialSessionTitle,
    this.initialOffset = 0,
    this.onSessionChanged,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<ChatMessage> _messages;
  late String _currentTitle;
  bool _isLoading = false;
  String _streamingContent = '';
  int _loadOffset = 0;
  bool _hasMore = false;
  String? _resumeSessionId;
  bool _showMarkdown = true;
  bool _showReasoning = true;
  bool _autoScroll = true;
  double _fontSize = 15.0;

  @override
  void initState() {
    super.initState();
    _messages = (widget.initialMessages ?? []).reversed.toList(); // 最新消息在前
    _currentTitle = widget.initialSessionTitle ?? '';
    if (widget.initialSessionId != null) {
      _resumeSessionId = widget.initialSessionId;
      widget.apiService.setSessionId(widget.initialSessionId!);
      _loadOffset = widget.initialOffset;
      _hasMore = true;
      widget.onSessionChanged?.call(widget.initialSessionId);
    }
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    _loadDisplayPrefs();
  }

  Future<void> _loadDisplayPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _showMarkdown = p.getBool('markdown') ?? true;
      _showReasoning = p.getBool('reasoning') ?? true;
      _autoScroll = p.getBool('auto_scroll') ?? true;
      final fs = p.getInt('font_size') ?? 1;
      _fontSize = [14.0, 15.0, 17.0][fs.clamp(0, 2)];
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _isLoading) return;
    // reverse:true 时 offset=0 在底部，maxScrollExtent 在顶部
    if (_scrollController.offset > _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── 附件选择 ──

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('添加附件', style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white.withAlpha(200),
              )),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachmentOption(Icons.camera_alt, '拍照', () {
                    Navigator.pop(ctx);
                    _showComingSoon();
                  }),
                  _attachmentOption(Icons.photo_library, '相册', () {
                    Navigator.pop(ctx);
                    _showComingSoon();
                  }),
                  _attachmentOption(Icons.insert_drive_file, '文件', () {
                    Navigator.pop(ctx);
                    _showComingSoon();
                  }),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withAlpha(30),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF6C63FF), size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(
            fontSize: 13, color: Colors.white.withAlpha(180),
          )),
        ],
      ),
    );
  }

  void _showComingSoon() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('文件/图片上传功能即将上线'),
          backgroundColor: const Color(0xFF6C63FF),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── 发送消息 ──

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.insert(0, userMsg);
      _isLoading = true;
      _streamingContent = '';
    });
    _scrollToBottom();

    try {
      await for (final delta in widget.apiService.sendMessageStream(text)) {
        setState(() {
          _streamingContent += delta;
        });
        _scrollToBottom();
      }

      if (_streamingContent.isNotEmpty) {
        setState(() {
          _messages.insert(0, ChatMessage(
            id: 'resp-${DateTime.now().millisecondsSinceEpoch}',
            content: _streamingContent,
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _streamingContent = '';
        });
      }
    } catch (e) {
      setState(() {
        _messages.insert(0, ChatMessage(
          id: 'err-${DateTime.now().millisecondsSinceEpoch}',
          content: '错误：$e',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
      final sid = widget.apiService.currentSessionId;
      if (sid != null) {
        _resumeSessionId = sid;
        _loadOffset = 0;
        _hasMore = true;
        widget.onSessionChanged?.call(sid);
      }
    }
  }

  // ── 构建 UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF0D0D1A),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF6C63FF),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _resumeSessionId != null ? _showRenameDialog : null,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _currentTitle.isNotEmpty ? _currentTitle : (_messages.any((m) => !m.isUser) ? '继续对话' : 'Hermes 聊天'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_resumeSessionId != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.edit_outlined, size: 13,
                            color: Colors.white.withAlpha(60)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        centerTitle: false,
        actions: [
          SizedBox(
            width: 36, height: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, size: 18, color: Color(0xFF6C63FF)),
              ),
              tooltip: '新对话',
              onPressed: () {
                widget.apiService.resetSession();
                widget.onSessionChanged?.call(null);
                setState(() => _messages.clear());
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: _messages.isEmpty && _streamingContent.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length + (_streamingContent.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_streamingContent.isNotEmpty && index == 0) {
                        return _buildMessageBubble(
                          ChatMessage(
                            id: 'streaming',
                            content: _streamingContent,
                            isUser: false,
                            timestamp: DateTime.now(),
                          ),
                          isStreaming: true,
                        );
                      }
                      final msgIdx = _streamingContent.isNotEmpty ? index - 1 : index;
                      return _buildMessageBubble(_messages[msgIdx]);
                    },
                  ),
          ),
          // 输入区域
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHistoryBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF6C63FF).withAlpha(30),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16, color: Color(0xFF6C63FF)),
          const SizedBox(width: 8),
          Text(
            '已恢复历史会话，继续对话',
            style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(150)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              widget.apiService.resetSession();
              setState(() => _messages.clear());
            },
            child: Text('新会话', style: TextStyle(fontSize: 12, color: const Color(0xFF6C63FF))),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(20)),
        ),
      ),
      padding: EdgeInsets.only(
        left: 4,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          // 附件按钮
          IconButton(
            icon: Icon(Icons.add_circle_outline,
                color: _isLoading ? Colors.white.withAlpha(40) : const Color(0xFF6C63FF)),
            onPressed: _isLoading ? null : _showAttachmentSheet,
          ),
          // 输入框
          Expanded(
            child: TextField(
              controller: _inputController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                hintText: '问 Hermes 点什么...',
                hintStyle: TextStyle(color: Colors.white.withAlpha(80)),
                filled: true,
                fillColor: const Color(0xFF2A2A3E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (text) {
                _inputController.clear();
                _sendMessage(text);
              },
            ),
          ),
          const SizedBox(width: 4),
          // 发送按钮
          CircleAvatar(
            backgroundColor: _isLoading
                ? Colors.grey.withAlpha(60)
                : const Color(0xFF6C63FF),
            child: IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              color: Colors.white,
              onPressed: _isLoading
                  ? null
                  : () {
                      final text = _inputController.text;
                      _inputController.clear();
                      _sendMessage(text);
                    },
            ),
          ),
        ],
      ),
    );
  }

  // ── 加载更多 ──

  Future<void> _loadMore() async {
    if (_resumeSessionId == null || _isLoading) return;

    _isLoading = true;

    final msgs = await widget.apiService.fetchSessionMessages(
      _resumeSessionId!,
      limit: 30,
      offset: _loadOffset,
    );

    final filtered = msgs
        .where((m) =>
            m['role'] != 'tool' &&
            m['role'] != 'system' &&
            m['content'] is String &&
            (m['content'] as String).isNotEmpty)
        .map((m) => ChatMessage(
              id: 'hist-${m.hashCode}',
              content: m['content'] as String,
              isUser: m['role'] == 'user' && !(m['content'] as String).startsWith('[IMPORTANT:'),
              timestamp: DateTime.now(),
              reasoning: m['reasoning'] as String?,
            ))
        .toList();

    if (filtered.isEmpty && msgs.isEmpty) {
      _hasMore = false;
      _isLoading = false;
      return;
    }

    setState(() {
      // reverse:true + 最新消息在索引0 → append 反转后的数据到末尾 = 正确的时间序
      _messages.addAll(filtered.reversed.toList());
      _loadOffset += msgs.length;
      _hasMore = msgs.length >= 30;
      _isLoading = false;
    });
    // 不需要调整滚动位置：现有消息（低索引）保持原位不动
  }

  // ── 空白状态 ──

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 80, color: Colors.white.withAlpha(30)),
          const SizedBox(height: 16),
          Text(
            '开始一段对话',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.white.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '消息会通过 API Server 发送到\\n你的 Hermes Agent\\n\\n支持图片上传和分析',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(60)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(
      text: _currentTitle,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('重命名会话', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: '输入新名称',
            hintStyle: TextStyle(color: Colors.white.withAlpha(60)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: const Color(0xFF2A2A3E),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(color: Colors.white.withAlpha(120))),
          ),
          FilledButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isEmpty || _resumeSessionId == null) return;
              final ok = await widget.apiService.renameSession(_resumeSessionId!, title);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (ok && mounted) {
                setState(() => _currentTitle = title);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  // ── 消息气泡 ──

  Widget _buildMessageBubble(ChatMessage msg, {bool isStreaming = false}) {
    final isUser = msg.isUser;
    final timeStr = _formatTime(msg.timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像（AI 有，用户有）
          CircleAvatar(
            radius: 14,
            backgroundColor: isUser
                ? const Color(0xFF6C63FF).withAlpha(80)
                : const Color(0xFF6C63FF),
            child: Icon(
              isUser ? Icons.person_outline : Icons.auto_awesome,
              size: 14,
              color: isUser ? const Color(0xFF6C63FF) : Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          // 内容区
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 角色标签 + 时间
                Row(
                  children: [
                    Text(isUser ? '你' : 'AI',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isUser
                                ? const Color(0xFF6C63FF)
                                : const Color(0xFF00BFA5))),
                    const SizedBox(width: 8),
                    Text(timeStr,
                        style: TextStyle(
                            fontSize: 11, color: Colors.white.withAlpha(60))),
                  ],
                ),
                const SizedBox(height: 4),
                // 思考过程（AI 消息）
                if (!isUser && _showReasoning && msg.reasoning != null && msg.reasoning!.isNotEmpty)
                  _buildReasoningBubble(msg.reasoning!),
                // 图片附件
                if (msg.hasImage) ...[
                  const SizedBox(height: 4),
                  _buildImageBubble(msg),
                ],
                // 文件附件
                if (msg.hasFile) ...[
                  const SizedBox(height: 4),
                  _buildFileBubble(msg),
                ],
                // 文本内容
                if (msg.content.isNotEmpty || isStreaming)
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF6C63FF)
                          : const Color(0xFF1E1E32),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildContentWidget(msg, isStreaming),
                        if (isStreaming)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white54,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // 空消息但有图片
                if (msg.content.isEmpty && !isStreaming && msg.hasImage)
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF6C63FF) : const Color(0xFF1E1E32),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text('📷 图片',
                        style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(150))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildContentWidget(ChatMessage msg, bool isStreaming) {
    if (isStreaming) {
      return Text(msg.content, style: TextStyle(fontSize: _fontSize, height: 1.4));
    }
    if (_showMarkdown) {
      return MarkdownBody(
        data: msg.content,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(fontSize: _fontSize, height: 1.4, color: Colors.white),
          h1: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, height: 1.4),
          h2: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, height: 1.4),
          h3: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, height: 1.4),
          code: TextStyle(fontSize: 13, color: const Color(0xFFFF7043),
              backgroundColor: Colors.black.withAlpha(80)),
          codeblockDecoration: BoxDecoration(
              color: Colors.black.withAlpha(80), borderRadius: BorderRadius.circular(8)),
          tableBorder: TableBorder.all(color: Colors.white.withAlpha(40), width: 0.5),
          tableHead: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
          tableBody: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13),
          tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          blockquoteDecoration: BoxDecoration(
              border: Border(left: BorderSide(color: const Color(0xFF6C63FF), width: 3)),
              color: Colors.white.withAlpha(5)),
          blockquote: TextStyle(color: Colors.white.withAlpha(150), fontStyle: FontStyle.italic),
          listBullet: const TextStyle(color: Color(0xFF6C63FF), fontSize: 15),
          horizontalRuleDecoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withAlpha(20)))),
          a: const TextStyle(color: Color(0xFF6C63FF), decoration: TextDecoration.underline),
        ),
      );
    }
    return Text(msg.content, style: TextStyle(fontSize: _fontSize, height: 1.4, color: Colors.white));
  }

  Widget _buildImageBubble(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: msg.localImagePath != null
            ? Image.file(
                File(msg.localImagePath!),
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _imagePlaceholder(),
              )
            : _imagePlaceholder(),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 200, height: 200,
      color: const Color(0xFF2A2A3E),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 48, color: Colors.white38),
      ),
    );
  }

  Widget _buildFileBubble(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A3E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withAlpha(15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 18, color: Color(0xFF6C63FF)),
            const SizedBox(width: 8),
            Text(msg.fileName ?? '文件',
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildReasoningBubble(String reasoning) {
    final wordCount = reasoning.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                content: SelectableText(
                  reasoning,
                  style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          },
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A3E).withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withAlpha(12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_outlined, size: 16,
                    color: Colors.white.withAlpha(120)),
                const SizedBox(width: 6),
                Text('思考过程 ($wordCount字)',
                    style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
                const Spacer(),
                Icon(Icons.touch_app, size: 14,
                    color: Colors.white.withAlpha(60)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
