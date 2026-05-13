import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/hermes_api.dart';

class ChatScreen extends StatefulWidget {
  final HermesApiService apiService;
  final String? initialSessionId;
  final List<ChatMessage>? initialMessages;
  final void Function(String? sessionId)? onSessionChanged;

  const ChatScreen({
    super.key,
    required this.apiService,
    this.initialSessionId,
    this.initialMessages,
    this.onSessionChanged,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<ChatMessage> _messages;
  bool _isLoading = false;
  String _streamingContent = '';
  int _loadOffset = 0;
  bool _hasMore = false;
  String? _resumeSessionId;

  @override
  void initState() {
    super.initState();
    _messages = widget.initialMessages ?? [];
    if (widget.initialSessionId != null) {
      _resumeSessionId = widget.initialSessionId;
      widget.apiService.setSessionId(widget.initialSessionId!);
      _loadOffset = widget.initialMessages?.length ?? 0;
      _hasMore = _loadOffset >= 30;
      widget.onSessionChanged?.call(widget.initialSessionId);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
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
      _messages.add(userMsg);
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
          _messages.add(ChatMessage(
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
        _messages.add(ChatMessage(
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
        widget.onSessionChanged?.call(sid);
      }
    }
  }

  // ── 构建 UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _messages.any((m) => !m.isUser) ? '继续对话' : 'Hermes 聊天',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: '新对话',
            onPressed: () {
              widget.apiService.resetSession();
              widget.onSessionChanged?.call(null);
              setState(() => _messages.clear());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 恢复历史会话提示
          if (widget.initialSessionId != null && _messages.length <= (widget.initialMessages?.length ?? 0))
            _buildHistoryBanner(),
          // 消息列表
          Expanded(
            child: _messages.isEmpty && _streamingContent.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length + (_streamingContent.isNotEmpty ? 1 : 0) + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      int msgIndex = index;
                      if (_hasMore) {
                        if (index == 0) return _buildLoadMoreButton();
                        msgIndex = index - 1;
                      }
                      if (msgIndex == _messages.length) {
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
                      return _buildMessageBubble(_messages[msgIndex]);
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
    setState(() => _isLoading = true);
    final msgs = await widget.apiService.fetchSessionMessages(
      _resumeSessionId!,
      limit: 30,
      offset: _loadOffset,
    );
    setState(() {
      if (msgs.isNotEmpty) {
        _messages.insertAll(0, msgs
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
            .toList());
        _loadOffset += msgs.length;
        _hasMore = msgs.length >= 30;
      } else {
        _hasMore = false;
      }
      _isLoading = false;
    });
  }

  Widget _buildLoadMoreButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton.icon(
          onPressed: _isLoading ? null : _loadMore,
          icon: _isLoading
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.expand_less, size: 18),
          label: Text(_isLoading ? '加载中...' : '加载更早的消息'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF6C63FF)),
        ),
      ),
    );
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

  // ── 消息气泡 ──

  Widget _buildMessageBubble(ChatMessage msg, {bool isStreaming = false}) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF6C63FF),
              child: Text('H', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 思考过程
                if (!isUser && msg.reasoning != null && msg.reasoning!.isNotEmpty)
                  _buildReasoningBubble(msg.reasoning!),
                // 图片附件（用户消息中的图片）
                if (isUser && msg.hasImage)
                  _buildImageBubble(msg),
                // 文件附件
                if (isUser && msg.hasFile)
                  _buildFileBubble(msg),
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
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
                        bottomRight: isUser ? Radius.zero : const Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.content,
                          style: const TextStyle(fontSize: 15, height: 1.4),
                        ),
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
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
              color: const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_outlined, size: 16, color: Colors.white.withAlpha(120)),
                const SizedBox(width: 6),
                Text('思考过程',
                    style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
                const SizedBox(width: 4),
                Icon(Icons.touch_app, size: 14, color: Colors.white.withAlpha(60)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
