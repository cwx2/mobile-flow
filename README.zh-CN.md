<p align="center">
  <img src="docs/assets/icon.png" width="100" alt="MobileFlow" />
</p>

<h1 align="center">MobileFlow</h1>

<p align="center">
  <strong>在手机上远程控制 Claude Code、OpenAI Codex、Aider、Gemini CLI、GitHub Copilot 等 AI 编程工具。</strong>
</p>

<p align="center">
  MobileFlow 是一个开源手机远程 AI 编程客户端。你可以在手机上和 AI Coding Agent 对话、浏览文件、运行终端命令、预览本地 Web 应用、管理 Git。
</p>

<p align="center">
  电脑负责运行编程工具，手机负责远程控制。
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
  <a href="#支持的-ai-编程工具">🤖 支持工具</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="#-连接模式">📡 连接模式</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="#常见问题">❓ FAQ</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="README.md">🌍 English</a>
</p>

---

<!-- ## 演示：在手机上控制 Claude Code -->
<!-- TODO: 添加 10 秒动图：连接 → 发任务给 Claude Code → 电脑执行 → 查看文件变化 → Git diff → 提交 -->

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

## 支持的 AI 编程工具

| 工具 | 状态 | 说明 |
|------|------|------|
| Claude Code | ✅ 已支持 | Anthropic 的 AI 编程 Agent |
| OpenAI Codex | ✅ 已支持 | OpenAI 的编程 CLI |
| Aider | ✅ 已支持 | 开源 AI 结对编程工具 |
| Gemini CLI | ✅ 已支持 | Google 的 AI 编程工具（有免费额度） |
| GitHub Copilot | ✅ 已支持 | GitHub 的 AI 助手 |
| Kiro CLI | ✅ 已支持 | AWS 的 AI 编程 Agent |
| 本地终端工具 | ✅ 已支持 | 电脑上的任何 CLI 工具 |
| Cline | 🔜 计划中 | VS Code AI 扩展 |

所有工具通过 [ACP（Agent Client Protocol）](https://github.com/anthropics/agent-client-protocol) 协议通信。

## ✨ 你能做什么

### 在手机上使用 Claude Code

在手机上和电脑上运行的 Claude Code 对话。发送编程任务、审查代码变更、批准文件修改 — 全在手机屏幕上完成。

### 在手机上使用 OpenAI Codex

远程控制 OpenAI Codex CLI。提交 prompt、观看代码生成、随时随地管理编程会话。

### 在手机上使用 Aider

从手机运行 Aider 结对编程会话。添加文件到上下文、发送指令、审查 AI 生成的 commit。

### 在手机上运行终端命令

完整的 PTY 终端支持。运行构建、安装依赖、查看日志、Ctrl+C 中断 — 和坐在电脑前一模一样。

### 在手机上管理 Git

查看 diff、暂存文件、提交、推送、拉取、切换分支、浏览提交历史。支持多仓库。

### 在手机上预览本地 Web 应用

手机上直接看到电脑运行的 Web 应用。不用部署就能测试响应式布局。

### 功能一览

- 🤖 **和 AI 对话** — Claude Code、Codex、Gemini CLI、Kiro、GitHub Copilot、Aider 等
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
pip install aider-chat                # Aider
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

## 常见问题

### 能在手机上用 Claude Code 吗？

可以。MobileFlow 让你从手机控制电脑上运行的 Claude Code。你可以完整使用聊天、文件浏览和终端功能。

### 能在手机上用 OpenAI Codex 吗？

可以。MobileFlow 支持远程控制 OpenAI Codex CLI。在电脑上安装 Codex，然后从手机控制它。

### 支持 Aider 吗？

支持。MobileFlow 支持 Aider 和其他终端类 AI 编程工具。电脑上能跑的 CLI 工具都可以从手机控制。

### 这是手机 IDE 吗？

不是。MobileFlow 不是手机 IDE。你的电脑运行编程工具，手机只是安全的远程遥控器。代码不会离开你的电脑。

### 能在手机上跑终端命令吗？

可以。MobileFlow 提供完整的 PTY 终端。运行任何命令、看实时输出、用 Ctrl+C 中断 — 和坐在电脑前一模一样。

### 能在手机上管理 Git 吗？

可以。你可以从手机查看 diff、暂存文件、提交、推送、拉取、切换分支、浏览提交历史。支持多仓库。

### 代码安全吗？

安全。所有通信端到端加密（AES-256 / NaCl SecretBox）。代码始终在你的电脑上，手机只是远程显示器。不涉及任何第三方服务器。

### 支持哪些 AI 工具？

Claude Code、OpenAI Codex、Aider、Gemini CLI、GitHub Copilot、Kiro CLI，以及任何终端类 AI 工具。MobileFlow 使用开放的 ACP 协议，新工具很容易接入。

## 关键词

手机编程、AI 编程 Agent、Claude Code 手机端、Codex 手机端、Aider 手机端、Gemini CLI 手机端、GitHub Copilot 手机端、手机远程编程、手机终端、手机管理 Git、移动端开发工具、远程开发、AI 结对编程、vibe coding、手机写代码。

## 🤝 参与贡献

发现 bug？有功能建议？[提一个 issue](../../issues) — 我们每条都看。

欢迎 Pull Request！请先阅读贡献指南。

## 许可证

[MIT](LICENSE)

---

<p align="center">
  <sub>为随时随地写代码的开发者而生 ❤️</sub>
</p>
