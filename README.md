# Hermes 聊天

一款 Android 移动端 AI 聊天客户端，通过 OpenAI Chat Completions 协议连接 [Hermes Agent](https://github.com/NousResearch/hermes-agent) API Server，实现实时对话、历史会话查看和使用统计。

> 🌐 全中文界面 | 🔐 支持 Tailscale 远程连接 | 📱 Android APK

---

## 项目架构

```
┌─────────────────────────────────────────────────┐
│            手机 (Android App)                    │
│  Hermes 聊天 (Flutter)                          │
│  ┌─────────────┐  ┌────────────┐  ┌───────────┐ │
│  │ 聊天界面     │  │ 历史会话    │  │ 个人中心   │ │
│  │ (SSE 流式)   │  │ (会话列表)  │  │ (统计)    │ │
│  └──────┬──────┘  └─────┬──────┘  └─────┬─────┘ │
│         │               │               │        │
│         └───────────────┼───────────────┘        │
│                         │                        │
│              HermesApiService                     │
└─────────────────────────┬───────────────────────┘
                          │ Tailscale 或局域网
                          ▼
┌─────────────────────────────────────────────────┐
│          WSL / 服务器 (Ubuntu)                   │
│                                                  │
│  Hermes Agent API Server (:8642)                 │
│  ┌─────────────────────────────────────────────┐ │
│  │ OpenAI Chat Completions API                 │ │
│  │ GET  /health                                │ │
│  │ POST /v1/chat/completions (流式/非流式)      │ │
│  │ GET  /v1/models                             │ │
│  │ Header: X-Hermes-Session-Id (会话续接)       │ │
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  会话历史后端 (:8080)                             │
│  ┌─────────────────────────────────────────────┐ │
│  │ Python HTTPServer (多线程)                   │ │
│  │ GET /api/sessions        ← 会话列表          │ │
│  │ GET /api/sessions/:id/messages ← 消息详情    │ │
│  │ GET /api/stats           ← 使用统计          │ │
│  │ GET /api/health          ← 健康检查          │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

---

## 功能特点

- **实时对话** — SSE 流式响应，逐字显示 AI 回复
- **会话续接** — 自动恢复上次会话上下文，继续对话
- **历史记录** — 浏览所有历史会话，查看详细对话内容
- **使用统计** — 今日/累计 Token 用量、缓存命中统计
- **连接配置** — 支持自定义服务器地址和 API 密钥
- **深色主题** — Material 3 深色设计，紫色主题色
- **Markdown 渲染** — AI 回复中的表格、代码块、列表等格式完整显示
- **统计详情** — 每日 Token 消耗趋势图 + 会话占比分析
- **会话重命名** — 聊天窗口内点击标题即可修改会话名称

---

## 快速开始

### 1. 启动 Hermes Agent API Server

确保已在服务器上安装并配置好 Hermes Agent：

```bash
# 安装（如未安装）
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash

# 设置 API Server 监听地址（允许远程访问）
hermes config set platforms.api_server.extra.host "0.0.0.0"
hermes config set platforms.api_server.extra.port 8642

# 设置 API 密钥（绑定 0.0.0.0 时必须）
hermes config set platforms.api_server.extra.key "your-api-key-here"

# 启动网关（API Server 作为网关平台运行）
hermes gateway run
```

### 2. 启动会话历史后端

```bash
cd chat_app
python3 server.py 8080
# → 访问 http://localhost:8080
```

### 3. 构建 APK

```bash
# 确保 Flutter SDK 已安装
flutter build apk --release --target-platform android-arm64

# APK 位于 build/app/outputs/flutter-apk/app-release.apk
```

---

## 远程访问（Tailscale）

App 通过 Tailscale 连接 WSL 上的 Hermes Agent，无需公网 IP：

```yaml
# 手机端 App 默认连接地址 (settings_screen.dart)
局域网: http://<WSL-IP>:8642
手机:   http://<Tailscale-IP>:8642
```

**WSL 上安装 Tailscale：**
```bash
# 添加 Tailscale 仓库
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main" | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt update && sudo apt install tailscale
sudo tailscale up
```

---

## API 参考

### Hermes API Server（OpenAI 兼容）

| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/v1/models` | GET | 可用模型列表 |
| `/v1/chat/completions` | POST | 对话（支持 `stream: true`） |

**请求头：**
- `Authorization: Bearer <api-key>`
- `X-Hermes-Session-Id: <session-id>`（续接会话时传入）

**流式响应格式（SSE）：**
```
data: {"choices":[{"delta":{"content":"你"}}]}
data: {"choices":[{"delta":{"content":"好"}}]}
data: [DONE]
```

### 会话历史后端

| 端点 | 说明 |
|------|------|
| `GET /api/sessions?limit=50` | 获取会话列表 |
| `GET /api/sessions/:id/messages?limit=30&offset=0` | 获取会话消息 |
| `GET /api/stats` | 使用统计 |
| `GET /api/health` | 健康检查 |

---

## 项目结构

```
chat_app/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── models/
│   │   └── chat_message.dart        # 消息模型
│   ├── screens/
│   │   ├── home_screen.dart         # 主页（底部导航）
│   │   ├── chat_screen.dart         # 聊天界面（SSE 流式）
│   │   ├── history_screen.dart      # 历史会话
│   │   ├── profile_screen.dart      # 个人中心/统计
│   │   └── settings_screen.dart     # 连接设置
│   └── services/
│       └── hermes_api.dart          # Hermes API 服务
├── server.py                        # 会话历史后端
├── pubspec.yaml                     # Flutter 依赖
└── README.md
```

---

## 技术栈

| 层 | 技术 |
|----|------|
| 客户端 | Flutter 3.7+ / Dart 3.7+ |
| 协议 | OpenAI Chat Completions API |
| 流式传输 | SSE (Server-Sent Events) |
| 后端 | Python HTTPServer（多线程） |
| 数据源 | Hermes Agent SessionDB (SQLite) |
| 远程连接 | Tailscale WireGuard VPN |
| 主题 | Material 3 + 深色模式 |
