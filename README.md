<p align="center">
  <img src="docs/assets/icon.png" width="100" alt="MobileFlow" />
</p>

<h1 align="center">MobileFlow</h1>

<p align="center">
  <strong>Your phone is now a coding terminal.<br/>Chat with AI, edit files, run commands, manage Git — all from your pocket.</strong>
</p>

<p align="center">
  <em>Mobile Remote for Desktop AI Coding Tools</em>
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/cwx2/mobile-flow?style=flat-square&color=43E6C3" alt="Release" /></a>
  <a href="../../releases/latest"><img src="https://img.shields.io/github/downloads/cwx2/mobile-flow/total?style=flat-square&color=69A8FF" alt="Downloads" /></a>
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/cwx2/mobile-flow?style=flat-square&color=FFD700" alt="Stars" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/cwx2/mobile-flow?style=flat-square&color=A78BFA" alt="License" /></a>
</p>

<p align="center">
  <a href="../../releases/latest">⬇️ Download</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="#-quick-start">🚀 Quick Start</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="#-connection-modes">📡 Connection Modes</a>&nbsp;&nbsp;•&nbsp;&nbsp;
  <a href="README.zh-CN.md">🇨🇳 中文</a>
</p>

---

## Why MobileFlow?

You're on the couch, in bed, or on the bus — and you want to check your code, ask AI a question, or push a quick fix. You don't want to open your laptop.

MobileFlow turns your phone into a remote control for your desktop AI coding tools. Your code never leaves your computer. The phone is just the screen.

## Screenshots

<table>
  <tr>
    <th>AI Chat</th>
    <th>Light Theme</th>
    <th>File Browser</th>
    <th>Terminal</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/chat.png" width="200" /></td>
    <td><img src="docs/screenshots/white-chat.png" width="200" /></td>
    <td><img src="docs/screenshots/files.png" width="200" /></td>
    <td><img src="docs/screenshots/terminal.png" width="200" /></td>
  </tr>
  <tr>
    <th>Git History</th>
    <th>Git Detail</th>
    <th>Settings</th>
    <th>File Editor</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/git-history.png" width="200" /></td>
    <td><img src="docs/screenshots/git-detail.png" width="200" /></td>
    <td><img src="docs/screenshots/setting.png" width="200" /></td>
    <td><img src="docs/screenshots/file-edit.png" width="200" /></td>
  </tr>
</table>

## ✨ What You Can Do

- 🤖 **Chat with AI** — Claude Code, Codex, Gemini CLI, Kiro, GitHub Copilot, and more
- 📁 **Browse & edit files** — syntax highlighting for 100+ languages, search
- 💻 **Full terminal** — run commands, see output, Ctrl+C to cancel
- 🔀 **Git everything** — diff, stage, commit, push, pull, switch branches, multi-repo
- 🖥️ **Live preview** — see your web app running on desktop, right on your phone
- ⚡ **Run configs** — launch, stop, and monitor dev servers remotely
- 🔌 **Slash commands** — CLI-advertised commands (/review, /compact) in chat menu
- 🔒 **End-to-end encrypted** — AES-256 / NaCl SecretBox, your code stays on your machine
- 📡 **Works anywhere** — same WiFi, remote relay, or self-hosted tunnel
- 🔄 **Session resume** — reconnect without losing AI conversation context

## 🚀 Quick Start

**3 steps, 2 minutes.**

**① Install Agent on your computer**

Download from [Releases](../../releases/latest) → run it → a tray icon appears with your IP and password.

| Platform | File |
|----------|------|
| Windows | `mobileflow-agent-windows.exe` |
| macOS | `mobileflow-agent-macos` |
| Linux | `mobileflow-agent-linux` |

Or run from source:
```bash
cd agent && pip install -e . && python -m mobileflow_agent
```

**② Install App on your phone**

Download the APK from [Releases](../../releases/latest) → install → enter IP, port `9600`, and password.

**③ Install an AI tool**

```bash
npm i -g @anthropic-ai/claude-code    # or any AI CLI you prefer
npm i -g @openai/codex                # OpenAI Codex
npm i -g @google/gemini-cli           # Gemini CLI (free tier)
```

That's it. Open the app, start chatting.

## 🏗️ How It Works

```
  📱 Phone                          💻 Computer
┌────────────┐   encrypted WS    ┌────────────────┐
│ Flutter    │◄──────────────────►│ Python Agent   │
│            │                    │                │
│ Chat UI    │                    │ AI CLI (ACP)   │
│ Files      │                    │ File System    │
│ Terminal   │                    │ Terminal PTY   │
│ Git        │                    │ Git            │
│ Preview    │                    │ Dev Server     │
└────────────┘                    └────────────────┘
```

The phone app is a thin UI layer — zero data storage. The Agent runs on your desktop, managing AI tools, files, and terminal sessions. All communication is encrypted via [ACP (Agent Client Protocol)](https://github.com/anthropics/agent-client-protocol).

## 🔐 Security

| | |
|---|---|
| 🔑 AES-256 / NaCl encryption | Every message encrypted, even on LAN |
| 🚫 Zero third-party servers | Direct connection, your code never leaves your machine |
| 🛡️ Brute-force protection | 3 failed attempts → 60s lockout |
| 🎫 Session tokens | Password only used once during pairing |
| 🔒 Tunnel mode | TLS + Bearer Token authentication |

## 📡 Connection Modes

| Mode | When to use | Security | Latency |
|------|-------------|----------|---------|
| **LAN** | Same WiFi | AES-256 after pairing | < 10ms |
| **Relay** | Different networks | E2E NaCl SecretBox | ~50-100ms |
| **Tunnel** | Self-hosted WSS | TLS + Bearer Token | Depends |

> 📖 Not on the same WiFi? See the [Remote Connection Guide](docs/remote-connection-guide.md) for relay and tunnel setup.

## Supported AI Tools

| Tool | Status |
|------|--------|
| Claude Code | ✅ Supported |
| OpenAI Codex | ✅ Supported |
| Gemini CLI | ✅ Supported |
| Kiro CLI | ✅ Supported |
| GitHub Copilot | ✅ Supported |
| Aider | ✅ Supported |
| Cline | 🔜 Planned |

All tools communicate via [ACP (Agent Client Protocol)](https://github.com/anthropics/agent-client-protocol).

## 🛠️ Development

```bash
# Agent (Python 3.10+)
cd agent
pip install -e ".[dev]"
pytest

# App (Flutter 3.3+)
cd app
flutter pub get
flutter test
flutter run
```

## 🤝 Contributing

Found a bug? Have a feature request? [Open an issue](../../issues) — we read every one.

Pull requests welcome! Please read the contributing guidelines first.

## License

[MIT](LICENSE)

---

<p align="center">
  <sub>Built with ❤️ for developers who code from anywhere.</sub>
</p>
