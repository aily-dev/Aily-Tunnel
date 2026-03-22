# 🚀 AilyTunnel v1.0 - Production-Grade Reverse Tunnel

[![Go Version](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go)](https://golang.org)
[![GitHub stars](https://img.shields.io/github/stars/aily-dev/Aily-Tunnel?style=social)](https://github.com/aily-dev/Aily-Tunnel/stars)
[![License](https://img.shields.io/github/license/aily-dev/Aily-Tunnel)](LICENSE)

**AilyTunnel** is a high-performance reverse tunnel written in pure Go. Supports **TCP/UDP forwarding** for VLESS, Trojan, VMess, Shadowsocks, WireGuard, gaming UDP & more.

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| **Multi-Transport** | TCP, **TLS**, **KCP** (low-latency), WebSocket, **Multipath** |
| **Production Ready** | Zero-copy (`splice(2)`), 512KB buffers, connection pooling |
| **Security** | Per-service tokens, IP ACL (CIDR), rate limiting, DDoS protection |
| **Performance** | QoS queues (high/normal/low), jitter buffer, pre-warmed pools |
| **Operations** | **Hot reload** (SIGHUP), Prometheus metrics, graceful shutdown |
| **Universal** | Tunnels **any TCP/UDP**: VLESS, Trojan, Shadowsocks, SOCKS5, HTTP, WireGuard |

## 🎯 Quick Start
```bash
curl -O https://raw.githubusercontent.com/aily-dev/Aily-Tunnel/main/Aily-Tunnel/install.sh
```

```bash
sudo bash install.sh
```
### 1️⃣ One-Command Install (Any Linux)

**Works on**: Ubuntu, Debian, CentOS, Fedora, Arch, Alpine, RHEL...

### 2️⃣ Generate Configs & Start
```bash
# Generates server.toml + client.toml + TLS certs
sudo ailytunnel-setup

# Server (Iran VPS)
sudo systemctl start ailytunnel-server

# Client  
sudo systemctl start ailytunnel-client
```

## 📦 Installation Options

### Option 1: Auto-Install Script (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/aily-dev/Aily-Tunnel/main/Aily-Tunnel/install.sh | sudo bash -s -- --server
```

### Option 2: Manual Build
```bash
git clone https://github.com/aily-dev/Aily-Tunnel.git
cd Aily-Tunnel
go mod tidy
go build -ldflags=\"-s -w\" -o ailytunnel .
sudo cp ailytunnel /usr/local/bin/
```

### Option 3: Docker
```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY . .
RUN go mod tidy && go build -ldflags='-s -w' -o ailytunnel .

FROM alpine:latest
COPY --from=builder /src/ailytunnel /usr/local/bin/
COPY server.toml /etc/ailytunnel/
CMD [\"ailytunnel\", \"--config\", \"/etc/ailytunnel/server.toml\"]
```

## ⚙️ Configuration

### Server Config (`/etc/ailytunnel/server.toml`)
```toml
[server]
bind_addr = \"0.0.0.0:2333\"
default_token = \"your-super-secret-token-here\"
metrics_addr = \"127.0.0.1:9090\"

[server.transport]
type = \"kcp\"  # tcp | tls | kcp | websocket

[server.transport.kcp]
key = \"your-super-secret-token-here\"
crypt = \"aes-128\"
mode = \"fast3\"
datashard = 10
parityshard = 3
dscp = 46

# VLESS TCP on port 443 (HIGH priority for speed)
[server.services.vless]
type = \"tcp\"
token = \"vless-token\"
bind_addr = \"0.0.0.0:443\"
priority = \"high\"
max_conn_rate = 200

# Gaming UDP
[server.services.gaming]
type = \"udp\"
token = \"gaming-token\"
bind_addr = \"0.0.0.0:7777\"
priority = \"high\"

# Rate limit + ACL
ip_whitelist = [\"178.22.122.100/32\"]  # Your client IP
ip_blacklist = [\"10.0.0.0/8\", \"192.168.0.0/16\"]
```

### Client Config (`/etc/ailytunnel/client.toml`)
```toml
[client]
remote_addr = \"YOUR_IRAN_VPS_IP:2333\"
default_token = \"your-super-secret-token-here\"
pool_size = 32
retry_interval = 3

[client.transport]
type = \"kcp\"

[client.services.vless]
type = \"tcp\"
token = \"vless-token\"
local_addr = \"127.0.0.1:10001\"  # Your local VLESS server
priority = \"high\"

[client.services.gaming]
type = \"udp\"
token = \"gaming-token\"
local_addr = \"127.0.0.1:7777\"
```

## 🔗 Supported Protocols

| Protocol | Type | Server Port | Client Port | Priority |
|----------|------|-------------|-------------|----------|
| VLESS | TCP | 443 | 10001 | High |
| Trojan | TCP | 2087 | 10002 | Normal |
| VMess | TCP | 8080 | 10003 | Normal |
| Shadowsocks | TCP | 8388 | 10004 | Normal |
| SOCKS5 Proxy | TCP | 1080 | 10005 | Normal |
| Gaming UDP | **UDP** | 7777 | 10008 | **High** |
| WireGuard | UDP | 51820 | 10007 | High |
| DNS Tunnel | UDP | 5353 | 10053 | Normal |

## 🚀 Performance Tuning

```
KCP \"fast3\" mode + FEC(10,3) = Gaming-grade latency
Multipath = Auto-failover + fastest path selection
Connection pool = 0-rtt tunnel setup (no handshake delay)
QoS queues = Gaming traffic bypasses bulk downloads
512KB socket buffers + zero-copy = Line-rate throughput
```

## 📊 Monitoring

**Prometheus Metrics**: `http://127.0.0.1:9090/metrics`

```
ailytunnel_connections_active
ailytunnel_bytes_total{service=\"vless\"}
ailytunnel_service_connections_total{service=\"gaming\"}
```

## 🔧 Operations

| Action | Command |
|--------|---------|
| Hot Reload Config | `kill -HUP \$(pgrep ailytunnel)` |
| Restart Service | `sudo systemctl restart ailytunnel-server` |
| View Logs | `sudo journalctl -u ailytunnel-server -f` |
| Check Status | `sudo systemctl status ailytunnel-server` |

## 🌐 Usage Examples

### 1. VLESS + Gaming Tunnel
```
Server (Iran VPS): exposes your VLESS 443 + UDP 7777 to the world
Client: forwards localhost:10001 → VPS:443, localhost:10008 → VPS:7777
```

### 2. WireGuard Site-to-Site
```
Server: bind_addr = \"0.0.0.0:51820\" udp
Client: local_addr = \"wg0\" udp
```

### 3. SOCKS5 Proxy Chain
```
Server: SOCKS5 on 1080 with IP whitelist
Client: local SOCKS5 → remote tunnel
```

## 🛡️ Security Hardening

```toml
# Per-IP limits
max_conn_rate = 100  # new conns/sec per IP

# Network ACL
ip_whitelist = [\"your.client.ip/32\"]
ip_blacklist = [\"10.0.0.0/8\", \"192.168.0.0/16\"]

# Bandwidth throttle
bandwidth_mbps = 100  # cap per service

# TLS (mutual auth)
[transport.tls]
cert = \"/etc/ssl/cert.pem\"
key  = \"/etc/ssl/key.pem\"
```

## 💻 Development

```bash
go mod tidy
go build -ldflags=\"-s -w -X main.Version=dev\" -gcflags=\"-B\" -trimpath
./ailytunnel --server --config ./server.toml
```

## 📄 License

MIT License - See [LICENSE](LICENSE)

## 🙌 Thanks

- [kcp-go](https://github.com/xtaci/kcp-go) - Ultra-fast UDP transport
- Built with ❤️ for high-performance tunneling

---

⭐ **Star this repo if AilyTunnel helps you!** ⭐
