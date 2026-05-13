import 'package:flutter/material.dart';
import '../services/hermes_api.dart';

class SettingsScreen extends StatefulWidget {
  final HermesApiService apiService;
  final Function(bool) onConnected;

  const SettingsScreen({
    super.key,
    required this.apiService,
    required this.onConnected,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _keyController;
  bool _isConnected = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.apiService.baseUrl);
    _keyController = TextEditingController(text: widget.apiService.apiKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    widget.apiService.configure(
      baseUrl: _urlController.text.trim(),
      apiKey: _keyController.text.trim(),
    );

    final ok = await widget.apiService.checkHealth();
    setState(() => _isConnected = ok);
    _isTesting = false;
    widget.onConnected(ok);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已连接到 Hermes！' : '连接失败'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 连接状态卡片
          Card(
            color: const Color(0xFF1A1A2E),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: _isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isConnected ? '已连接' : '未连接',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _isConnected ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '本地地址: localhost:8642\n'
                    '手机连接: 通过 Tailscale (100.126.192.84:8642)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withAlpha(100),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 服务器地址
          Text('服务器地址', style: TextStyle(color: Colors.white.withAlpha(150))),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'http://100.x.x.x:8642',
              filled: true,
              fillColor: const Color(0xFF1A1A2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.link, size: 20),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
          const SizedBox(height: 16),

          // API Key
          Text('API 密钥', style: TextStyle(color: Colors.white.withAlpha(150))),
          const SizedBox(height: 8),
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: '不设密钥则留空',
              filled: true,
              fillColor: const Color(0xFF1A1A2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.key, size: 20),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
          const SizedBox(height: 24),

          // 测试连接按钮
          FilledButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(_isTesting ? '测试中...' : '测试连接'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 参考信息
          Text(
            '参考信息',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(150),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('API 类型', 'OpenAI Chat Completions'),
                _infoRow('流式传输', 'SSE 事件流'),
                _infoRow('默认端口', '8642'),
                _infoRow('认证方式', 'Bearer Token'),
                _infoRow('Tailscale IP', '100.126.192.84'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withAlpha(100),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
