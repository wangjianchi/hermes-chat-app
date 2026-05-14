import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class HermesApiService {
  String _baseUrl;
  String _apiKey;
  String? _currentSessionId;

  HermesApiService({
    String? baseUrl,
    String apiKey = '2695304d643dbded7a8a5a1b2d7d9520',
  })  : _baseUrl = baseUrl ?? (kIsWeb
          ? 'http://localhost:8642'
          : 'http://100.126.192.84:8642'),
        _apiKey = apiKey;

  String get baseUrl => _baseUrl;
  String get apiKey => _apiKey;
  String? get currentSessionId => _currentSessionId;

  /// 从 URL 中提取主机地址（用于连接本地后端服务器）
  String get _host {
    final uri = Uri.parse(_baseUrl);
    return '${uri.host}:${uri.port}';
  }

  void configure({required String baseUrl, String apiKey = ''}) {
    _baseUrl = baseUrl;
    _apiKey = apiKey;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_apiKey';
    }
    if (_currentSessionId != null) {
      headers['X-Hermes-Session-Id'] = _currentSessionId!;
    }
    return headers;
  }

  /// 构建消息内容数组（支持文本+多图片）
  List<dynamic> _buildContent(String text, {ChatMessage? attachment}) {
    if (attachment == null || (!attachment.hasImage && !attachment.hasFile)) {
      return [{'type': 'text', 'text': text}];
    }

    final parts = <dynamic>[];
    if (text.isNotEmpty) {
      parts.add({'type': 'text', 'text': text});
    }

    // 图片附件
    if (attachment.hasImage) {
      final b64 = attachment.imageBase64;
      final mime = attachment.mimeType ?? 'image/jpeg';
      if (b64 != null) {
        parts.add({
          'type': 'image_url',
          'image_url': {'url': 'data:$mime;base64,$b64'},
        });
      }
    }

    // 文件附件 — 作为 text 发送（带文件名标记）
    if (attachment.hasFile && attachment.fileBase64 != null) {
      // 大文件用 base64 发可能太大，转成 text content
      try {
        final fileContent = utf8.decode(base64Decode(attachment.fileBase64!));
        parts.add({
          'type': 'text',
          'text': '--- 文件: ${attachment.fileName} ---\n$fileContent',
        });
      } catch (_) {
        // 二进制文件无法解码，用文本提示
        parts.add({
          'type': 'text',
          'text': '[文件: ${attachment.fileName} (${_formatSize(attachment.fileSize ?? 0)}) 已上传，请查看]',
        });
      }
    }

    return parts;
  }

  String _formatSize(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)}MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${bytes}B';
  }

  /// 构建消息对象
  Map<String, dynamic> _buildMessage(String role, String text, {ChatMessage? attachment}) {
    final content = _buildContent(text, attachment: attachment);
    if (content.length == 1 && content[0]['type'] == 'text') {
      return {'role': role, 'content': content[0]['text']};
    }
    return {'role': role, 'content': content};
  }

  /// 发送消息（流式，支持图片/文件）
  Stream<String> sendMessageStream(String message, {ChatMessage? attachment}) async* {
    final messages = <Map<String, dynamic>>[];

    // 只在首次会话且没有附件时加 system prompt
    if (_currentSessionId == null && attachment == null) {
      messages.add({'role': 'system', 'content': 'You are a helpful AI assistant.'});
    }

    messages.add(_buildMessage('user', message, attachment: attachment));

    final body = jsonEncode({
      'model': 'hermes-agent',
      'messages': messages,
      'stream': true,
    });

    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl/v1/chat/completions'));
      request.headers.addAll(_headers);
      request.body = body;

      final http.StreamedResponse response = await request.send();

      if (response.statusCode != 200) {
        final error = await response.stream.bytesToString();
        yield 'Error (${response.statusCode}): $error';
        return;
      }

      final sessionId = response.headers['x-hermes-session-id'];
      if (sessionId != null && sessionId.isNotEmpty) {
        _currentSessionId = sessionId;
      }

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') return;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final choices = json['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;
                if (delta != null && delta['content'] != null) {
                  yield delta['content'] as String;
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      yield 'Connection error: $e';
    }
  }

  /// 发送消息（非流式）
  Future<ChatMessage> sendMessage(String message) async {
    final body = jsonEncode({
      'model': 'hermes-agent',
      'messages': [
        {'role': 'system', 'content': 'You are a helpful AI assistant.'},
        {'role': 'user', 'content': message},
      ],
      'stream': false,
    });

    final response = await http.post(
      Uri.parse('$_baseUrl/v1/chat/completions'),
      headers: _headers,
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode} ${response.body}');
    }

    _currentSessionId = response.headers['x-hermes-session-id'];

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = json['choices']?[0]?['message']?['content'] as String? ?? '';

    return ChatMessage(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: false,
      timestamp: DateTime.now(),
    );
  }

  /// 检查连接（返回延迟毫秒）
  Future<int> checkHealthWithLatency() async {
    try {
      final stopwatch = Stopwatch()..start();
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 5));
      stopwatch.stop();
      if (response.statusCode == 200) return stopwatch.elapsedMilliseconds;
      return -1;
    } catch (_) {
      return -1;
    }
  }

  /// 获取会话历史主机地址（从 API 地址推导）
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取会话历史（从本地后端服务器）
  Future<List<Map<String, dynamic>>> fetchSessions({int limit = 50}) async {
    try {
      final host = kIsWeb ? 'localhost:8080' : '100.126.192.84:8080';
      final response = await http.get(
        Uri.parse('http://$host/api/sessions?limit=$limit'),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  /// 获取指定会话的消息列表
  Future<List<Map<String, dynamic>>> fetchSessionMessages(String sessionId, {int limit = 30, int offset = 0}) async {
    try {
      final host = kIsWeb ? 'localhost:8080' : '100.126.192.84:8080';
      final response = await http.get(
        Uri.parse('http://$host/api/sessions/$sessionId/messages?limit=$limit&offset=$offset'),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  /// 重命名会话
  Future<bool> renameSession(String sessionId, String title) async {
    try {
      final host = kIsWeb ? 'localhost:8080' : '100.126.192.84:8080';
      final response = await http.post(
        Uri.parse('http://$host/api/sessions/$sessionId/rename'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': title}),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 重置会话（开始新对话）
  void resetSession() {
    _currentSessionId = null;
  }

  /// 设置当前会话 ID（用于恢复历史会话）
  void setSessionId(String id) {
    _currentSessionId = id;
  }
}
