class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? reasoning;

  // 图片/文件附件
  final String? localImagePath; // 本地图片路径（用于预览）
  final String? imageBase64;    // 图片 base64（用于发送）
  final String? mimeType;      // 图片 MIME 类型
  final String? fileName;      // 文件名
  final String? fileBase64;    // 文件 base64
  final int? fileSize;         // 文件大小 byte

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.reasoning,
    this.localImagePath,
    this.imageBase64,
    this.mimeType,
    this.fileName,
    this.fileBase64,
    this.fileSize,
  });

  bool get hasImage => imageBase64 != null || localImagePath != null;
  bool get hasFile => fileName != null && fileBase64 != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'hasImage': hasImage,
        'hasFile': hasFile,
        'fileName': fileName,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        content: json['content'] as String,
        isUser: json['isUser'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class Conversation {
  final String sessionId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  Conversation({
    required this.sessionId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  String get preview =>
      messages.isNotEmpty ? messages.last.content : '(empty)';

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        sessionId: json['sessionId'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        messages: (json['messages'] as List)
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}
