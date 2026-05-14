import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  late TextEditingController _urlCtrl;
  late TextEditingController _keyCtrl;
  bool _showKey = false;
  bool _isTesting = false;
  int _latency = -1;
  bool _connected = false;

  // 显示设置
  bool _markdown = true;
  bool _reasoning = true;
  bool _autoScroll = true;
  int _fontSize = 1; // 0=小 1=中 2=大

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.apiService.baseUrl);
    _keyCtrl = TextEditingController(text: widget.apiService.apiKey);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _markdown = p.getBool('markdown') ?? true;
      _reasoning = p.getBool('reasoning') ?? true;
      _autoScroll = p.getBool('auto_scroll') ?? true;
      _fontSize = p.getInt('font_size') ?? 1;
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('markdown', _markdown);
    await p.setBool('reasoning', _reasoning);
    await p.setBool('auto_scroll', _autoScroll);
    await p.setInt('font_size', _fontSize);
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    widget.apiService.configure(
      baseUrl: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
    );
    final ms = await widget.apiService.checkHealthWithLatency();
    setState(() {
      _isTesting = false;
      _latency = ms;
      _connected = ms >= 0;
    });
    widget.onConnected(_connected);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_connected ? '连接成功' : '连接失败'),
        backgroundColor: _connected ? Colors.green : Colors.red,
      ));
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = [14.0, 15.0, 17.0][_fontSize];
    return Scaffold(
      appBar: AppBar(
        elevation: 0, scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFF0D0D1A),
        title: const Text('设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('连接'),
          const SizedBox(height: 10),
          _buildConnectCard(),
          const SizedBox(height: 24),
          _sectionTitle('显示'),
          const SizedBox(height: 10),
          _buildDisplayCard(fontSize),
          const SizedBox(height: 24),
          _sectionTitle('关于'),
          const SizedBox(height: 10),
          _buildAboutCard(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
        color: Colors.white.withAlpha(150)));
  }

  // ── 连接 ──

  Widget _buildConnectCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态行
          Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _connected ? const Color(0xFF00BFA5) : (_latency == -1 ? Colors.white24 : Colors.red),
                ),
              ),
              const SizedBox(width: 8),
              Text(_connected ? '已连接' : (_latency == -1 ? '未测试' : '连接失败'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                      color: _connected ? const Color(0xFF00BFA5) : Colors.white54)),
              if (_latency >= 0) ...[
                const Spacer(),
                Text('${_latency}ms', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(80))),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _label('Hermes API 地址'),
          const SizedBox(height: 6),
          _input(_urlCtrl, 'http://100.126.192.84:8642', Icons.link),
          const SizedBox(height: 12),
          _label('API 密钥（可选）'),
          const SizedBox(height: 6),
          TextField(
            controller: _keyCtrl,
            obscureText: !_showKey,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              hintText: '不设密钥则留空',
              hintStyle: TextStyle(color: Colors.white.withAlpha(40)),
              filled: true, fillColor: const Color(0xFF0D0D1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.key, size: 18),
              suffixIcon: IconButton(
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.wifi_tethering, size: 18),
              label: Text(_isTesting ? '测试中...' : '测试连接'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 显示 ──

  Widget _buildDisplayCard(double fontSize) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _switchRow('Markdown 渲染', 'AI 回复中的表格、代码块等格式显示', _markdown, (v) {
            setState(() => _markdown = v);
            _savePrefs();
          }),
          const Divider(height: 24, color: Color(0xFF2A2A3E)),
          _switchRow('思考过程', '显示 AI 的推理过程标签', _reasoning, (v) {
            setState(() => _reasoning = v);
            _savePrefs();
          }),
          const Divider(height: 24, color: Color(0xFF2A2A3E)),
          _switchRow('自动滚到底部', '新消息自动滚动到最新位置', _autoScroll, (v) {
            setState(() => _autoScroll = v);
            _savePrefs();
          }),
          const Divider(height: 24, color: Color(0xFF2A2A3E)),
          Row(
            children: [
              const Icon(Icons.text_fields, size: 18, color: Colors.white54),
              const SizedBox(width: 10),
              Text('字体大小', style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(180))),
              const Spacer(),
              _sizeBtn('小', 0),
              const SizedBox(width: 6),
              _sizeBtn('中', 1),
              const SizedBox(width: 6),
              _sizeBtn('大', 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sizeBtn(String label, int idx) {
    final active = _fontSize == idx;
    return GestureDetector(
      onTap: () {
        setState(() => _fontSize = idx);
        _savePrefs();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF6C63FF) : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(
            fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? Colors.white : Colors.white54)),
      ),
    );
  }

  Widget _switchRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(180))),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(60))),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF6C63FF),
        ),
      ],
    );
  }

  // ── 关于 ──

  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _aboutRow('应用版本', '1.0.0+2'),
          const Divider(height: 20, color: Color(0xFF2A2A3E)),
          _aboutRow('框架', 'Flutter / Dart'),
          const Divider(height: 20, color: Color(0xFF2A2A3E)),
          _aboutRow('后端协议', 'OpenAI Chat Completions'),
          const Divider(height: 20, color: Color(0xFF2A2A3E)),
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  child: Text('源代码', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(150))),
                ),
                const Icon(Icons.open_in_new, size: 16, color: Color(0xFF6C63FF)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(100))),
        ),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  // ── 通用组件 ──

  Widget _label(String t) {
    return Text(t, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(100)));
  }

  Widget _input(TextEditingController c, String hint, IconData icon) {
    return TextField(
      controller: c,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withAlpha(40)),
        filled: true, fillColor: const Color(0xFF0D0D1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        prefixIcon: Icon(icon, size: 18),
      ),
    );
  }
}
