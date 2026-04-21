# MobileFlow 远程连接指南

## 三种连接方式概览

| 方式 | 场景 | 安全性 | 速度 | 需要服务器 |
|------|------|--------|------|-----------|
| LAN 直连 | 同一 WiFi | 高（认证后加密） | 最快（1-5ms） | 不需要 |
| Relay 中继 | 任意网络 | 最高（端到端加密） | 中等（50-200ms） | 需要中继服务器 |
| Tunnel 隧道 | 任意网络 | 高（TLS 加密） | 中等（20-100ms） | 需要网关服务器 |

---

## 方式一：LAN 直连

手机和电脑在同一个 WiFi 下直接连接，零配置。

### 基本步骤

1. 电脑上启动 Agent（双击运行或命令行 `mobileflow-agent`）
2. 从系统托盘查看 IP、端口（默认 9600）和连接密码
3. 手机 App → LAN 模式 → 输入 IP、端口、密码 → 连接

### 场景示例

**在家写代码**：电脑和手机连同一个家庭 WiFi，直接输入电脑 IP 连接。

**公司内网**：电脑插网线、手机连公司 WiFi，只要在同一个子网就能连。部分公司 WiFi 会隔离设备，如果连不上试试下面的虚拟组网方案。

**虚拟组网（Tailscale / ZeroTier）**：不在同一网络也能用 LAN 模式。安装 Tailscale 或 ZeroTier 后，两台设备会分配虚拟 IP（100.x.x.x），用虚拟 IP 代替局域网 IP 即可。

```bash
# Tailscale 安装后，电脑和手机用同一账号登录
# 电脑的 Tailscale IP 类似 100.64.0.1
# 手机 App 用 LAN 模式连接 100.64.0.1:9600
```

### 连不上？排查清单

- [ ] 电脑防火墙是否放行了 9600 端口
- [ ] 手机和电脑是否在同一个子网（IP 前三段相同）
- [ ] Agent 是否正在运行（检查系统托盘图标）
- [ ] 电脑浏览器访问 `http://电脑IP:9600` 是否有响应

---

## 方式二：Relay 中继

通过中继服务器转发消息。端到端加密，中继服务器无法解密你的数据。适合手机和电脑不在同一网络的场景。

### 基本步骤

1. 部署或接入一个 Relay Server
2. 电脑 Agent 配置 Relay Server 地址并启动
3. Agent 生成配对码（或 QR 码）
4. 手机 App → Relay 模式 → 输入配对码或扫码 → 自动建立加密通道

### 场景示例

**在外面连家里电脑**：电脑在家里开着 Agent + Relay 模式，你在咖啡厅用手机 App 输入配对码连接。数据经过中继服务器转发，但中继看不到内容。

**出差连公司电脑**：公司电脑开着 Agent，你在酒店用手机连接。不需要 VPN，不需要公网 IP，配对码一次配对后自动重连。

**多人协作**：团队共享一个 Relay Server，每个人的电脑都连上去。手机 App 通过不同的配对码连接不同的电脑。

### 自建 Relay Server

```bash
# 在一台有公网 IP 的服务器上部署（Docker 方式）
docker run -d -p 8080:8080 mobileflow/relay-server

# 电脑 Agent 配置
# 在 Agent 设置中填入 Relay Server 地址：ws://你的服务器IP:8080
```

### 安全机制

- 配对码通过线下方式交换（扫码或手动输入），不经过网络
- 配对成功后生成 NaCl SecretBox 密钥，所有后续通信端到端加密
- 中继服务器只做转发，无法解密任何内容
- 即使中继服务器被攻破，攻击者也只能看到加密数据

---

## 方式三：Tunnel 隧道

通过内网穿透工具把电脑的 Agent 端口暴露到公网。适合有自己服务器或熟悉运维的用户。

### 场景示例

**Cloudflare Tunnel（海外用户推荐，免费）**：不需要自己的服务器，Cloudflare 提供免费隧道。

```bash
# 1. 安装 cloudflared（https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/）
# 2. 创建隧道
cloudflared tunnel --url ws://localhost:9600
# 输出类似：https://xxx-yyy-zzz.trycloudflare.com
# 3. 手机 App → Tunnel 模式 → 输入上面的地址
```

**frp（国内用户推荐）**：需要一台有公网 IP 的云服务器（阿里云/腾讯云轻量服务器，最低几十块/月）。

```ini
# === 服务器端 frps.toml ===
bindPort = 7000

# === 电脑端 frpc.toml ===
serverAddr = "你的服务器公网IP"
serverPort = 7000

[[proxies]]
name = "mobileflow"
type = "tcp"
localIP = "127.0.0.1"
localPort = 9600
remotePort = 9600
```

```bash
# 服务器上启动
./frps -c frps.toml

# 电脑上启动
./frpc -c frpc.toml

# 手机 App → Tunnel 模式 → 连接 wss://服务器IP:9600
```

**ngrok（快速测试，免费额度有限）**：一行命令，适合临时使用。

```bash
# 1. 注册 ngrok 账号（https://ngrok.com）
# 2. 安装并认证
ngrok config add-authtoken 你的token
# 3. 启动隧道
ngrok http 9600
# 输出类似：https://xxxx.ngrok-free.app
# 4. 手机 App → Tunnel 模式 → 输入上面的地址
```

### 安全建议

- 强烈建议配置 TLS（HTTPS/WSS），避免明文传输
- Cloudflare Tunnel 自带 TLS，frp 和 ngrok 需要额外配置
- 设置 Bearer Token 认证，防止未授权访问
- 定期更换 Token


---

## 虚拟组网工具对比

不在同一网络时，除了 Relay 和 Tunnel，还可以用虚拟组网工具让设备"假装"在同一个局域网，然后用 LAN 模式连接。

| 工具 | 免费额度 | 国内体验 | 安装难度 |
|------|---------|---------|---------|
| [Tailscale](https://tailscale.com) | 100 台设备 | 一般 | 最简单 |
| [ZeroTier](https://zerotier.com) | 10 台设备 | 较好 | 简单 |
| [Headscale](https://github.com/juanfont/headscale) | 无限（自建） | 取决于服务器 | 需要运维能力 |

国内用户如果 Tailscale 连接不稳定，推荐试 ZeroTier。

---

## 安全性对比

| 方面 | LAN 直连 | Relay 中继 | Tunnel 隧道 |
|------|---------|-----------|------------|
| 传输加密 | NaCl 加密 | 端到端 NaCl 加密 | TLS 加密 |
| 密钥交换 | 密码认证（ws://） | QR 码/配对码线下交换 | Bearer Token |
| 中间人风险 | 局域网内可嗅探握手 | 无（端到端） | TLS 终端可解密 |
| 推荐场景 | 信任的网络 | 任何网络 | 自建基础设施 |

> 💡 用 Tailscale/ZeroTier + LAN 模式，可以同时获得虚拟组网的便利和 WireGuard 的加密保护。
