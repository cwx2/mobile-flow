<p align="center">
  <img src="docs/assets/icon.png" width="100" alt="MobileFlow" />
</p>

<h1 align="center">MobileFlow</h1>

<p align="center">
  <strong>手机变成编程终端。<br/>和 AI 对话、编辑文件、跑命令、管理 Git — 全在口袋里。</strong>
</p>

<p align="center">
  <em>桌面 AI 编程工具的手机遥控器</em>
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/cwx2/mobile-flow?style=flat-square&color=43E6C3" alt="Release" /></a>
  <a href="../../releases/latest"><img src="https://img.shields.io/github/downloads/cwx2/mobile-flow/total?style=flat-square&color=69A8FF" alt="Downloads" /></a>
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/cwx2/mobile-flow?style=flat-square&color=FFD700" alt="Stars" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/cwx2/mobile-flow?style=flat-square&color=A78BFA" alt="License" /></a>
</p>

<p align="center">
  <a href="../../releases/latest">⬇️ 下载</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="#-快速开始">🚀 快速开始</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="#-连接模式">📡 连接模式</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="README.md">🌍 English</a>
</p>

---

## 为什么用 MobileFlow？

你躺在沙发上、床上、或者公交车上 — 想看看代码、问 AI 一个问题、或者推一个小修复。但你不想打开电脑。

MobileFlow 把你的手机变成桌面 AI 编程工具的遥控器。代码始终在你的电脑上，手机只是屏幕。

## 截图

<table>
  <tr>
    <th>AI 对话</th>
    <th>浅色主题</th>
    <th>文件浏览</th>
    <th>终端</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/chat.png" width="200" /></td>
    <td><img src="docs/screenshots/white-chat.png" width="200" /></td>
    <td><img src="docs/screenshots/files.png" width="200" /></td>
    <td><img src="docs/screenshots/terminal.png" width="200" /></td>
  </tr>
  <tr>
    <th>Git 历史</th>
    <th>Git 详情</th>
    <th>设置</th>
    <th>代码编辑</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/git-history.png" width="200" /></td>
    <td><img src="docs/screenshots/git-detail.png" width="200" /></td>
    <td><img src="docs/screenshots/setting.png" width="200" /></td>
    <td><img src="docs/screenshots/file-edit.png" width="200" /></td>
  </tr>
</table>

## ✨ 你能做什么

- 🤖 **和 AI 对话** — Claude Code、Codex、Gemini CLI、Kiro、GitHub Copilot 等
- 📁 **浏览和编辑文件** — 100+ 语言语法高亮、搜索
- 💻 **完整终端** — 跑命令、看输出、Ctrl+C 中断
- 🔀 **Git 全功能** — diff、暂存、提交、推送、拉取、切换分支、多仓库
- 🖥️ **实时预览** — 手机上直接看电脑运行的 Web 应用
- ⚡ **运行配置** — 远程启动、停止、监控开发服务器
- 🔌 **斜杠命令** — CLI 提供的命令（/review、/compact）直接在聊天菜单中使用
- 🔒 **端到端加密** — AES-256 / NaCl SecretBox，代码不离开你的电脑
- 📡 **随处可用** — 同一 WiFi、远程中继、或自建隧道
- 🔄 **会话恢复** — 断线重连不丢失 AI 对话上下文

## 🚀 快速开始

**3 步，2 分钟。**

**① 电脑上安装 Agent**

从 [Releases](../../releases/latest) 下载 → 运行 → 系统托盘出现图标，显示 IP 和密码。

| 平台 | 文件 |
|------|------|
| Windows | `mobileflow-agent-windows.exe` |
| macOS | `mobileflow-agent-macos` |
| Linux | `mobileflow-agent-linux` |

或从源码运行：
```bash
cd agent && pip install -e . && python -m mobileflow_agent
```

**② 手机上安装 App**

从 [Releases](../../releases/latest) 下载 APK → 安装 → 输入 IP、端口 `9600` 和密码。

**③ 安装一个 AI 工具**

```bash
npm i -g @anthropic-ai/claude-code    # 或者你喜欢的任何 AI CLI
npm i -g @openai/codex                # OpenAI Codex
npm i -g @google/gemini-cli           # Gemini CLI（有免费额度）
```

搞定。打开 App，开始对话。

## 🏗️ 工作原理

```
  📱 手机                           💻 电脑
┌────────────┐   加密 WebSocket   ┌────────────────┐
│ Flutter    │◄──────────────────►│ Python Agent   │
│            │                    │                │
│ 聊天 UI    │                    │ AI CLI (ACP)   │
│ 文件       │                    │ 文件系统        │
│ 终端       │                    │ 终端 PTY       │
│ Git        │                    │ Git            │
│ 预览       │                    │ 开发服务器      │
└────────────┘                    └────────────────┘
```

手机 App 是纯 UI 层 — 零数据存储。Agent 运行在你的电脑上，管理 AI 工具、文件和终端会话。所有通信通过 [ACP（Agent Client Protocol）](https://github.com/anthropics/agent-client-protocol) 加密传输。

## 🔐 安全

| | |
|---|---|
| 🔑 AES-256 / NaCl 加密 | 每条消息都加密，即使在局域网 |
| 🚫 零第三方服务器 | 直连，代码不离开你的电脑 |
| 🛡️ 暴力破解保护 | 3 次失败 → 锁定 60 秒 |
| 🎫 会话令牌 | 密码只在配对时使用一次 |
| 🔒 隧道模式 | TLS + Bearer Token 认证 |

## 📡 连接模式

| 模式 | 适用场景 | 安全性 | 延迟 |
|------|---------|--------|------|
| **局域网** | 同一 WiFi | AES-256 配对加密 | < 10ms |
| **中继** | 不同网络 | E2E NaCl SecretBox | ~50-100ms |
| **隧道** | 自建 WSS 服务器 | TLS + Bearer Token | 取决于服务器 |

> 📖 不在同一 WiFi？查看[远程连接指南](docs/remote-connection-guide.md)了解中继和隧道配置。

## 支持的 AI 工具

| 工具 | 状态 |
|------|------|
| Claude Code | ✅ 已支持 |
| OpenAI Codex | ✅ 已支持 |
| Gemini CLI | ✅ 已支持 |
| Kiro CLI | ✅ 已支持 |
| GitHub Copilot | ✅ 已支持 |
| Aider | ✅ 已支持 |
| Cline | 🔜 计划中 |

所有工具通过 [ACP（Agent Client Protocol）](https://github.com/anthropics/agent-client-protocol) 协议通信。

## 🛠️ 开发

```bash
# Agent（Python 3.10+）
cd agent
pip install -e ".[dev]"
pytest

# App（Flutter 3.3+）
cd app
flutter pub get
flutter test
flutter run
```

## 🤝 参与贡献

发现 bug？有功能建议？[提一个 issue](../../issues) — 我们每条都看。

欢迎 Pull Request！请先阅读贡献指南。

## 许可证

[MIT](LICENSE)

---

<p align="center">
  <sub>为随时随地写代码的开发者而生 ❤️</sub>
</p>
