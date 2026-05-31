# MobileFlow Remote Connection Guide

## Connection Methods Overview

| Method | Scenario | Security | Speed | Server Required |
|--------|----------|----------|-------|-----------------|
| LAN Direct | Same WiFi | High (encrypted after auth) | Fastest (1-5ms) | No |
| Relay | Any network | Highest (E2E encrypted) | Medium (50-200ms) | Relay server |
| Tunnel | Any network | High (TLS encrypted) | Medium (20-100ms) | Gateway server |

---

## Method 1: LAN Direct

Phone and computer on the same WiFi, zero configuration.

### Basic Steps

1. Launch Agent on computer (double-click or run `mobileflow-agent`)
2. Check IP, port (default 9600), and password from system tray
3. Phone App → LAN mode → enter IP, port, password → Connect

### Example Scenarios

**Coding at home**: Computer and phone on the same home WiFi. Enter the computer's IP and connect.

**Office network**: Computer on ethernet, phone on office WiFi. Works as long as they're on the same subnet. Some corporate WiFi isolates devices — try the virtual network option below.

**Virtual network (Tailscale / ZeroTier)**: Use LAN mode even across different networks. After installing Tailscale or ZeroTier, both devices get virtual IPs (100.x.x.x). Use the virtual IP instead of the LAN IP.

```bash
# After installing Tailscale, sign in with the same account on both devices
# Computer's Tailscale IP looks like 100.64.0.1
# Phone App → LAN mode → connect to 100.64.0.1:9600
```

### Can't connect? Checklist

- [ ] Is the computer firewall allowing port 9600?
- [ ] Are phone and computer on the same subnet (first 3 IP octets match)?
- [ ] Is Agent running (check system tray icon)?
- [ ] Can you access `http://computer-IP:9600` from the computer's browser?

---

## Method 2: Relay

Messages forwarded through a relay server. End-to-end encrypted — the relay cannot read your data. Best for when phone and computer are on different networks.

### Basic Steps

1. Deploy or connect to a Relay Server
2. Configure Agent with the Relay Server address and start it
3. Agent generates a pairing code (or QR code)
4. Phone App → Relay mode → enter pairing code or scan QR → encrypted channel established

### Example Scenarios

**Connect to home computer from outside**: Computer at home running Agent + Relay mode. You're at a coffee shop, enter the pairing code on your phone. Data goes through the relay but the relay can't read it.

**Business trip, connect to office computer**: Office computer running Agent. You're at a hotel connecting via phone. No VPN needed, no public IP needed. Auto-reconnects after initial pairing.

**Team collaboration**: Team shares a Relay Server. Each person's computer connects to it. Phone App uses different pairing codes to connect to different computers.

### Self-hosted Relay Server

```bash
# Deploy on a server with a public IP (Docker)
docker run -d -p 8080:8080 mobileflow/relay-server

# Configure Agent with the Relay Server address:
# ws://your-server-ip:8080
```

### Security Mechanism

- Pairing codes exchanged offline (QR scan or manual input), never over the network
- After pairing, NaCl SecretBox key is generated for all subsequent E2E encrypted communication
- Relay server only forwards data, cannot decrypt anything
- Even if the relay server is compromised, attackers only see encrypted data


---

## Method 3: Tunnel

Expose the computer's Agent port to the internet via tunneling tools. Best for users with their own servers or ops experience.

### Example Scenarios

**Cloudflare Tunnel (recommended for international users, free)**:  No server needed, Cloudflare provides free tunnels.

```bash
# 1. Install cloudflared (https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)
# 2. Create tunnel
cloudflared tunnel --url ws://localhost:9600
# Output: https://xxx-yyy-zzz.trycloudflare.com
# 3. Phone App → Tunnel mode → enter the URL above
```

**frp (recommended for China-based users)**: Requires a cloud server with a public IP (Alibaba Cloud / Tencent Cloud, starting from a few dollars/month).

```ini
# === Server: frps.toml ===
bindPort = 7000

# === Computer: frpc.toml ===
serverAddr = "your-server-public-ip"
serverPort = 7000

[[proxies]]
name = "mobileflow"
type = "tcp"
localIP = "127.0.0.1"
localPort = 9600
remotePort = 9600
```

```bash
# Start on server
./frps -c frps.toml

# Start on computer
./frpc -c frpc.toml

# Phone App → Tunnel mode → connect to wss://server-ip:9600
```

**ngrok (quick testing, limited free tier)**: One command, great for temporary use.

```bash
# 1. Sign up at https://ngrok.com
# 2. Install and authenticate
ngrok config add-authtoken your-token
# 3. Start tunnel
ngrok http 9600
# Output: https://xxxx.ngrok-free.app
# 4. Phone App → Tunnel mode → enter the URL above
```

### Security Tips

- Strongly recommend configuring TLS (HTTPS/WSS) to avoid plaintext transmission
- Cloudflare Tunnel includes TLS by default; frp and ngrok need extra configuration
- Set up Bearer Token authentication to prevent unauthorized access
- Rotate tokens periodically

---

## Virtual Network Tools Comparison

When not on the same network, besides Relay and Tunnel, you can use virtual network tools to make devices appear on the same LAN, then connect via LAN mode.

| Tool | Free Tier | Global Experience | Setup Difficulty |
|------|-----------|-------------------|-----------------|
| [Tailscale](https://tailscale.com) | 100 devices | Good | Easiest |
| [ZeroTier](https://zerotier.com) | 10 devices | Good (Asia nodes) | Easy |
| [Headscale](https://github.com/juanfont/headscale) | Unlimited (self-hosted) | Depends on server | Requires ops skills |

---

## Security Comparison

| Aspect | LAN Direct | Relay | Tunnel |
|--------|-----------|-------|--------|
| Transport | NaCl encryption | E2E NaCl encryption | TLS encryption |
| Key Exchange | Password auth (ws://) | QR/pairing code offline | Bearer Token |
| MITM Risk | LAN sniffing possible during handshake | None (E2E) | TLS termination can decrypt |
| Recommended For | Trusted networks | Any network | Self-hosted infrastructure |

> 💡 Using Tailscale/ZeroTier + LAN mode gives you both the convenience of virtual networking and WireGuard encryption protection.
