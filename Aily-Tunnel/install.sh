#!/usr/bin/env bash
# ============================================================
#  AilyTunnel v5.0 — Complete Auto Setup
#  Works on: Ubuntu · Debian · CentOS · Rocky · AlmaLinux
#             Fedora · RHEL · Arch · Alpine · Any Linux
#  Auto: installs Go · builds binary · installs service
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'
MAGENTA='\033[0;35m'; NC='\033[0m'

OK="${GREEN}[  OK  ]${NC}"; FAIL="${RED}[ FAIL ]${NC}"
WARN="${YELLOW}[ WARN ]${NC}"; INFO="${CYAN}[ INFO ]${NC}"; QQ="${YELLOW}[  ??  ]${NC}"

ok()   { echo -e "${OK}   $*"; }
fail() { echo -e "${FAIL} $*"; }
warn() { echo -e "${WARN} $*"; }
info() { echo -e "${INFO} $*"; }
ask()  { echo -e "${QQ}   $*"; }
step() { echo -e "\n${BOLD}${BLUE}━━━  $*  ━━━${NC}"; }
hr()   { echo -e "${BLUE}────────────────────────────────────────────────────${NC}"; }
die()  { echo -e "${FAIL} $*"; exit 1; }

# ── Globals ──────────────────────────────────────────────
VERSION="5.0.0"
GO_VERSION="1.22.3"
BINARY="/usr/local/bin/ailytunnel"
CFG_DIR="/etc/ailytunnel"
SVC="ailytunnel"
GO_DIR="/usr/local/go"
GO_BIN="${GO_DIR}/bin/go"

# ── Root check ───────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

# ════════════════════════════════════════════════════════
# OS & Package Manager Detection
# Works on any Linux distro
# ════════════════════════════════════════════════════════
detect_os() {
    OS_ID=""
    PKG=""

    # Try /etc/os-release first (most modern distros)
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID:-}"
    fi

    # Detect package manager
    if command -v apt-get &>/dev/null; then
        PKG="apt"
    elif command -v yum &>/dev/null; then
        PKG="yum"
    elif command -v dnf &>/dev/null; then
        PKG="dnf"
    elif command -v pacman &>/dev/null; then
        PKG="pacman"
    elif command -v apk &>/dev/null; then
        PKG="apk"
    elif command -v zypper &>/dev/null; then
        PKG="zypper"
    else
        PKG="unknown"
    fi

    info "OS: ${OS_ID:-unknown} | Package manager: ${PKG}"
}

# ════════════════════════════════════════════════════════
# Install system dependencies
# ════════════════════════════════════════════════════════
install_deps() {
    step "Installing system dependencies"

    case "$PKG" in
        apt)
            apt-get update -qq 2>/dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                curl wget tar gzip jq openssl iproute2 iptables \
                ca-certificates ufw 2>/dev/null || true
            ;;
        yum)
            yum install -y -q curl wget tar gzip jq openssl \
                iproute iptables ca-certificates 2>/dev/null || true
            ;;
        dnf)
            dnf install -y -q curl wget tar gzip jq openssl \
                iproute iptables ca-certificates 2>/dev/null || true
            ;;
        pacman)
            pacman -Sy --noconfirm curl wget tar gzip jq openssl \
                iproute2 iptables ca-certificates 2>/dev/null || true
            ;;
        apk)
            apk add --no-cache curl wget tar gzip jq openssl \
                iproute2 iptables ca-certificates 2>/dev/null || true
            ;;
        zypper)
            zypper install -y curl wget tar gzip jq openssl \
                iproute2 iptables ca-certificates 2>/dev/null || true
            ;;
        *)
            warn "Unknown package manager — skipping dep install"
            warn "Make sure curl, wget, tar, openssl are installed"
            ;;
    esac

    ok "Dependencies ready"
}

# ════════════════════════════════════════════════════════
# Go Installation
# Downloads official Go binary — works on any Linux
# ════════════════════════════════════════════════════════
install_go() {
    # Make sure Go is in PATH for this session
    export PATH=$PATH:${GO_DIR}/bin

    # Check if Go is already installed and usable
    if command -v go &>/dev/null; then
        local VER; VER=$(go version 2>/dev/null | awk '{print $3}')
        info "Go ${VER} already installed"
        return 0
    fi

    # Check if Go is installed but not in PATH
    if [[ -x "$GO_BIN" ]]; then
        info "Go found at ${GO_BIN} — adding to PATH"
        export PATH=$PATH:${GO_DIR}/bin
        return 0
    fi

    step "Installing Go ${GO_VERSION}"

    # Detect CPU architecture
    local ARCH; ARCH=$(uname -m)
    local GA
    case "$ARCH" in
        x86_64|amd64)   GA="amd64"  ;;
        aarch64|arm64)  GA="arm64"  ;;
        armv7l|armv6l)  GA="armv6l" ;;
        i386|i686)      GA="386"    ;;
        s390x)          GA="s390x"  ;;
        ppc64le)        GA="ppc64le";;
        mips*)          GA="mips"   ;;
        *)
            die "Unsupported CPU architecture: $ARCH"
            ;;
    esac

    local GO_URL="https://go.dev/dl/go${GO_VERSION}.linux-${GA}.tar.gz"
    local GO_TMP="/tmp/go_install_$$.tar.gz"

    info "Downloading Go ${GO_VERSION} (${GA}) ..."
    info "URL: ${GO_URL}"

    # Try wget first, then curl
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$GO_TMP" "$GO_URL" || \
        wget -q -O "$GO_TMP" "$GO_URL" || \
        die "wget failed to download Go"
    elif command -v curl &>/dev/null; then
        curl -# -L -o "$GO_TMP" "$GO_URL" || \
        die "curl failed to download Go"
    else
        die "Neither wget nor curl found — cannot download Go"
    fi

    # Verify download
    [[ -f "$GO_TMP" && -s "$GO_TMP" ]] || die "Go download failed or empty file"

    info "Extracting Go to ${GO_DIR} ..."
    rm -rf "$GO_DIR"
    tar -C /usr/local -xzf "$GO_TMP"
    rm -f "$GO_TMP"

    # Verify extraction
    [[ -x "$GO_BIN" ]] || die "Go binary not found after extraction"

    # Add to PATH permanently for all users
    local GO_PATH_LINE='export PATH=$PATH:/usr/local/go/bin'

    # /etc/profile (works for all shells on login)
    grep -qxF "$GO_PATH_LINE" /etc/profile 2>/dev/null || \
        echo "$GO_PATH_LINE" >> /etc/profile

    # /etc/environment (Debian/Ubuntu)
    if [[ -f /etc/environment ]]; then
        if ! grep -q '/usr/local/go/bin' /etc/environment 2>/dev/null; then
            sed -i 's|PATH="\(.*\)"|PATH="\1:/usr/local/go/bin"|' /etc/environment 2>/dev/null || true
        fi
    fi

    # /etc/profile.d/ (works on most distros)
    echo "$GO_PATH_LINE" > /etc/profile.d/go.sh
    chmod +x /etc/profile.d/go.sh

    # Also add to current session
    export PATH=$PATH:${GO_DIR}/bin

    # Final check
    if ! command -v go &>/dev/null; then
        die "Go installed but 'go' command still not found in PATH"
    fi

    local INSTALLED_VER; INSTALLED_VER=$(go version | awk '{print $3}')
    ok "Go ${INSTALLED_VER} installed successfully"
}

# ════════════════════════════════════════════════════════
# Build AilyTunnel from source
# ════════════════════════════════════════════════════════
build() {
    export PATH=$PATH:${GO_DIR}/bin

    step "Building AilyTunnel v${VERSION}"

    # Find source file — look next to this script
    local SDIR; SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local SRC=""

    if [[ -f "$SDIR/ailytunnel.go" ]]; then
        SRC="$SDIR/ailytunnel.go"
        info "Found ailytunnel.go in: ${SDIR}"
    elif [[ -f "$SDIR/main.go" ]]; then
        SRC="$SDIR/main.go"
        info "Found main.go in: ${SDIR} (using as source)"
    else
        fail "Source file not found!"
        info "Expected: ${SDIR}/ailytunnel.go"
        info "Or:       ${SDIR}/main.go"
        die "Place ailytunnel.go next to this script and retry"
    fi

    # Build directory
    local D="/tmp/aily-build-$$"
    rm -rf "$D"
    mkdir -p "$D"

    # Copy source
    cp "$SRC" "${D}/main.go"
    info "Source: ${SRC}"

    # go.mod
    cat > "${D}/go.mod" << 'GOMOD'
module ailytunnel
go 1.21
require (
    github.com/BurntSushi/toml v1.3.2
    github.com/xtaci/kcp-go/v5 v5.6.18
    github.com/gorilla/websocket v1.5.1
)
GOMOD

    cd "$D"

    # Download dependencies with retry
    info "Downloading Go modules (may take a moment)..."
    local TIDY_OK=0
    for attempt in 1 2 3; do
        if go mod tidy 2>&1; then
            TIDY_OK=1
            break
        fi
        warn "go mod tidy attempt ${attempt} failed — retrying..."
        sleep 3
    done
    [[ $TIDY_OK -eq 1 ]] || die "Failed to download Go modules after 3 attempts"

    # Build binary
    info "Compiling AilyTunnel..."
    local BUILD_OUT
    BUILD_OUT=$(CGO_ENABLED=0 go build \
        -ldflags="-s -w -X main.Version=${VERSION}" \
        -trimpath \
        -o "${D}/ailytunnel" . 2>&1) || {
        echo "$BUILD_OUT"
        # Try without -trimpath for older Go versions
        warn "Retrying build without -trimpath..."
        CGO_ENABLED=0 go build \
            -ldflags="-s -w -X main.Version=${VERSION}" \
            -o "${D}/ailytunnel" . || die "Build failed"
    }

    # Verify binary was created
    [[ -f "${D}/ailytunnel" ]] || die "Build succeeded but binary not found"
    [[ -s "${D}/ailytunnel" ]] || die "Binary is empty — build failed"

    # Install binary
    info "Installing binary to ${BINARY} ..."
    cp "${D}/ailytunnel" "$BINARY"
    chmod +x "$BINARY"

    # Cleanup
    cd /
    rm -rf "$D"

    # Verify installation
    if ! command -v ailytunnel &>/dev/null; then
        # Try direct path
        if [[ -x "$BINARY" ]]; then
            ok "Binary installed at ${BINARY}"
        else
            die "Binary installation failed"
        fi
    fi

    # Show version / help to confirm it works
    echo ""
    echo -e "${CYAN}── Binary info ──────────────────────────${NC}"
    $BINARY --help 2>&1 | head -5 || true
    echo -e "${CYAN}─────────────────────────────────────────${NC}"
    echo ""

    ok "AilyTunnel v${VERSION} built and installed → ${BINARY}"
}

# ════════════════════════════════════════════════════════
# Force rebuild (ignores existing binary)
# ════════════════════════════════════════════════════════
force_build() {
    rm -f "$BINARY"
    build
}

# ── Firewall ─────────────────────────────────────────────
open_port() {
    local port=$1 proto=${2:-tcp}
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "${port}/${proto}" &>/dev/null || true
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/${proto}" &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
    elif command -v iptables &>/dev/null; then
        iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
    fi
    ok "Port ${port}/${proto} opened"
}

# ── Systemd service ───────────────────────────────────────
create_service() {
    local mode=$1 cfg=$2

    # Check if systemd is available
    if ! command -v systemctl &>/dev/null; then
        warn "systemd not found — creating init.d script instead"
        create_initd "$mode" "$cfg"
        return
    fi

    cat > "/etc/systemd/system/${SVC}.service" << EOF
[Unit]
Description=AilyTunnel v${VERSION} (${mode})
Documentation=https://github.com/ailytunnel
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BINARY} --${mode} ${cfg}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=512000
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SVC}
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SVC" &>/dev/null
    ok "systemd service created"
}

# Fallback for systems without systemd (OpenRC, SysV)
create_initd() {
    local mode=$1 cfg=$2
    local INITD="/etc/init.d/${SVC}"
    cat > "$INITD" << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ${SVC}
# Required-Start:    \$network
# Required-Stop:     \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       AilyTunnel reverse tunnel
### END INIT INFO

DAEMON=${BINARY}
ARGS="--${mode} ${cfg}"
PIDFILE=/var/run/${SVC}.pid

case "\$1" in
    start)
        echo "Starting ${SVC}..."
        start-stop-daemon --start --background --make-pidfile \
            --pidfile "\$PIDFILE" --exec "\$DAEMON" -- \$ARGS
        ;;
    stop)
        echo "Stopping ${SVC}..."
        start-stop-daemon --stop --pidfile "\$PIDFILE"
        rm -f "\$PIDFILE"
        ;;
    restart) \$0 stop; sleep 1; \$0 start ;;
    status)
        if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
            echo "${SVC} is running"
        else
            echo "${SVC} is not running"
        fi
        ;;
    *) echo "Usage: \$0 {start|stop|restart|status}"; exit 1 ;;
esac
EOF
    chmod +x "$INITD"
    if command -v update-rc.d &>/dev/null; then
        update-rc.d "$SVC" defaults &>/dev/null || true
    elif command -v rc-update &>/dev/null; then
        rc-update add "$SVC" default &>/dev/null || true
    fi
    ok "init.d script created at ${INITD}"
}

start_service() {
    if command -v systemctl &>/dev/null; then
        systemctl start "$SVC"
    else
        "/etc/init.d/${SVC}" start
    fi
}

status_service() {
    if command -v systemctl &>/dev/null; then
        systemctl status "$SVC"
    else
        "/etc/init.d/${SVC}" status
    fi
}

# ── Helpers ───────────────────────────────────────────────
get_ip()     { curl -s4 --max-time 5 ifconfig.me 2>/dev/null || \
               curl -s4 --max-time 5 api.ipify.org 2>/dev/null || \
               curl -s4 --max-time 5 icanhazip.com 2>/dev/null || \
               echo "unknown"; }
valid_port() { [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
gen_token()  { openssl rand -hex 16 2>/dev/null || \
               head -c 32 /dev/urandom | base64 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 32 || \
               cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 32; }

# ── Self-signed TLS cert ──────────────────────────────────
gen_tls_cert() {
    local OUT=$1
    mkdir -p "$OUT"
    [[ -f "${OUT}/cert.pem" && -f "${OUT}/key.pem" ]] && {
        info "TLS cert already exists"; return; }
    info "Generating self-signed TLS certificate..."
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "${OUT}/key.pem" -out "${OUT}/cert.pem" \
        -subj "/CN=ailytunnel" 2>/dev/null
    ok "TLS cert: ${OUT}/cert.pem"
}

# ════════════════════════════════════════════════════════
# Transport selection
# ════════════════════════════════════════════════════════
select_transport() {
    echo ""
    echo -e "${BOLD}Select tunnel transport:${NC}"
    hr
    echo "  1) TCP       — standard TCP. Reliable, universal."
    echo "  2) TLS       — encrypted TCP. Secure + hides traffic."
    echo -e "  3) ${MAGENTA}KCP${NC}       — UDP-based. Best for gaming & low latency."
    echo "               Forward Error Correction + DSCP marking."
    echo "  4) WebSocket — HTTP upgrade. CDN-friendly."
    echo -e "  5) ${MAGENTA}Multipath${NC} — KCP over multiple paths simultaneously."
    echo "               Picks the fastest path for each packet."
    hr
    ask "Transport [1-5, default: 1]:"
    read -r TR; TR=${TR:-1}

    case "$TR" in
        2) TRANSPORT="tls" ;;
        3) TRANSPORT="kcp" ;;
        4) TRANSPORT="websocket" ;;
        5) TRANSPORT="multipath" ;;
        *) TRANSPORT="tcp" ;;
    esac

    if [[ "$TRANSPORT" == "kcp" || "$TRANSPORT" == "multipath" ]]; then
        echo ""
        echo -e "${BOLD}KCP mode:${NC}"
        echo "  1) fast3  — lowest latency (gaming)"
        echo "  2) fast2  — balanced"
        echo "  3) fast   — moderate"
        echo "  4) normal — like TCP"
        ask "Mode [1-4, default: 1]:"; read -r KM
        case "${KM:-1}" in
            2) KCP_MODE="fast2" ;; 3) KCP_MODE="fast" ;;
            4) KCP_MODE="normal" ;; *) KCP_MODE="fast3" ;;
        esac

        ask "FEC data shards [default: 10]:"; read -r DS; DS=${DS:-10}
        ask "FEC parity shards [default: 3]:"; read -r PS; PS=${PS:-3}

        echo ""
        echo -e "${BOLD}KCP encryption:${NC}"
        echo "  1) aes-128   2) chacha20   3) none"
        ask "Choice [1-3, default: 1]:"; read -r ENC
        case "${ENC:-1}" in
            2) KCP_CRYPT="chacha20" ;; 3) KCP_CRYPT="none" ;;
            *) KCP_CRYPT="aes-128" ;;
        esac

        if [[ "$TRANSPORT" == "multipath" ]]; then
            ask "Additional control ports (space-separated, e.g: 2334 2335):"
            read -r EXTRA_PORTS; EXTRA_PORTS=${EXTRA_PORTS:-}
        fi
        ok "KCP: mode=${KCP_MODE} fec=${DS}+${PS} crypt=${KCP_CRYPT}"
    fi

    [[ "$TRANSPORT" == "tls" ]] && USE_TLS_CERT=1 || USE_TLS_CERT=0
}

# ── Build transport config block ──────────────────────────
build_transport_block() {
    local token=$1 side=$2

    local KCP_BLOCK="" TLS_BLOCK="" WS_BLOCK="" MP_BLOCK=""

    if [[ "$TRANSPORT" == "kcp" || "$TRANSPORT" == "multipath" ]]; then
        KCP_BLOCK="
[${side}.transport.kcp]
key = \"${token}\"
crypt = \"${KCP_CRYPT:-aes-128}\"
mode = \"${KCP_MODE:-fast3}\"
mtu = 1350
sndwnd = 2048
rcvwnd = 2048
datashard = ${DS:-10}
parityshard = ${PS:-3}
dscp = 46
nocomp = false
sockbuf = 524288"
    fi

    if [[ "$TRANSPORT" == "multipath" && "$side" == "client" && -n "${EXTRA_PORTS:-}" ]]; then
        local PA="[\"${IRAN_IP}:${CTRL}\""
        for EP in $EXTRA_PORTS; do PA="${PA}, \"${IRAN_IP}:${EP}\""; done
        PA="${PA}]"
        MP_BLOCK="
[${side}.transport.multipath]
enabled = true
paths = ${PA}"
    fi

    if [[ "$TRANSPORT" == "tls" ]]; then
        if [[ "$side" == "server" ]]; then
            TLS_BLOCK="
[${side}.transport.tls]
cert = \"${CFG_DIR}/cert.pem\"
key  = \"${CFG_DIR}/key.pem\""
        else
            TLS_BLOCK="
[${side}.transport.tls]
ca  = \"\"
sni = \"\""
        fi
    fi

    [[ "$TRANSPORT" == "websocket" ]] && WS_BLOCK="
[${side}.transport.websocket]
tls = false"

    local ACTUAL="$TRANSPORT"
    [[ "$TRANSPORT" == "multipath" ]] && ACTUAL="kcp"

    echo "
[${side}.transport]
type = \"${ACTUAL}\"

[${side}.transport.tcp]
nodelay = true
keepalive_secs = 10
${TLS_BLOCK}${KCP_BLOCK}${WS_BLOCK}${MP_BLOCK}"
}

# ── Protocol selection ────────────────────────────────────
select_protocols() {
    echo ""
    echo -e "${BOLD}Select protocols to tunnel:${NC}"
    hr
    echo -e "  ${CYAN}── TCP ──${NC}"
    echo "   1) VLESS          (server: 443   client: 10001)"
    echo "   2) Trojan         (server: 2087  client: 10002)"
    echo "   3) VMess          (server: 8080  client: 10003)"
    echo "   4) Shadowsocks    (server: 8388  client: 10004)"
    echo "   5) SOCKS5         (server: 1080  client: 10005)"
    echo "   6) HTTP Proxy     (server: 8118  client: 10006)"
    echo ""
    echo -e "  ${MAGENTA}── UDP ──${NC}"
    echo "   7) Shadowsocks UDP(server: 8389  client: 10044)"
    echo "   8) WireGuard      (server: 51820 client: 10007)"
    echo -e "   9) ${BOLD}Gaming UDP${NC}      (server: 7777  client: 10008) priority=high"
    echo "  10) DNS tunnel     (server: 5353  client: 10053)"
    echo "  11) Custom TCP"
    echo "  12) Custom UDP"
    hr
    ask "Numbers separated by space (e.g: 1 2 9):"
    read -r PROTO_NUMS
}

# ── Build service entries ─────────────────────────────────
build_service_entries() {
    local token=$1 side=$2
    SVC_BLOCK=""; PORTS_TO_OPEN=(); CLIENT_SVCS=""

    for NUM in $PROTO_NUMS; do
        case "$NUM" in
            1)  NAME="vless";       TYPE="tcp"; PRIO="normal"; DS2="443";   DC="10001" ;;
            2)  NAME="trojan";      TYPE="tcp"; PRIO="normal"; DS2="2087";  DC="10002" ;;
            3)  NAME="vmess";       TYPE="tcp"; PRIO="normal"; DS2="8080";  DC="10003" ;;
            4)  NAME="shadowsocks"; TYPE="tcp"; PRIO="normal"; DS2="8388";  DC="10004" ;;
            5)  NAME="socks5";      TYPE="tcp"; PRIO="normal"; DS2="1080";  DC="10005" ;;
            6)  NAME="http_proxy";  TYPE="tcp"; PRIO="normal"; DS2="8118";  DC="10006" ;;
            7)  NAME="ss_udp";      TYPE="udp"; PRIO="normal"; DS2="8389";  DC="10044" ;;
            8)  NAME="wireguard";   TYPE="udp"; PRIO="high";   DS2="51820"; DC="10007" ;;
            9)  NAME="gaming_udp";  TYPE="udp"; PRIO="high";   DS2="7777";  DC="10008" ;;
            10) NAME="dns_tunnel";  TYPE="udp"; PRIO="high";   DS2="5353";  DC="10053" ;;
            11) ask "Custom TCP name:"; read -r NAME; NAME=${NAME:-custom_tcp}
                TYPE="tcp"; PRIO="normal"; DS2="9000"; DC="10090" ;;
            12) ask "Custom UDP name:"; read -r NAME; NAME=${NAME:-custom_udp}
                TYPE="udp"; PRIO="normal"; DS2="9001"; DC="10091" ;;
            *) warn "Unknown: $NUM"; continue ;;
        esac

        if [[ "$side" == "iran" ]]; then
            ask "Bind port for ${NAME} [default: ${DS2}]:"
            read -r SP; SP=${SP:-$DS2}
            valid_port "$SP" || { warn "Invalid — skipping ${NAME}"; continue; }

            ask "Client local port for ${NAME} [default: ${DC}]:"
            read -r CP; CP=${CP:-$DC}
            valid_port "$CP" || { warn "Invalid — skipping ${NAME}"; continue; }

            ask "Max conn/sec per IP for ${NAME} [0=unlimited, default: 100]:"
            read -r MCR; MCR=${MCR:-100}

            ask "Bandwidth limit Mbps for ${NAME} [0=unlimited, default: 0]:"
            read -r BW; BW=${BW:-0}

            SVC_BLOCK+="
[server.services.${NAME}]
type = \"${TYPE}\"
token = \"${token}\"
bind_addr = \"0.0.0.0:${SP}\"
nodelay = true
priority = \"${PRIO}\"
max_conn_rate = ${MCR}
bandwidth_mbps = ${BW}
ip_whitelist = []
ip_blacklist = []
"
            PORTS_TO_OPEN+=("${SP}:${TYPE}")
            CLIENT_SVCS+="${NAME}:${TYPE}:${CP}:${PRIO}:${BW}\n"
            ok "Added ${NAME} (${TYPE}) → server port: ${SP}"

        else
            ask "Local address for ${NAME} [default: 127.0.0.1:${DC}]:"
            read -r LOCAL; LOCAL="${LOCAL:-127.0.0.1:${DC}}"

            ask "Bandwidth limit Mbps for ${NAME} [0=unlimited, default: 0]:"
            read -r BW; BW=${BW:-0}

            SVC_BLOCK+="
[client.services.${NAME}]
type = \"${TYPE}\"
token = \"${token}\"
local_addr = \"${LOCAL}\"
nodelay = true
priority = \"${PRIO}\"
bandwidth_mbps = ${BW}
"
            ok "Added ${NAME} → ${LOCAL}"
        fi
    done
}

# ════════════════════════════════════════════════════════
# SETUP: Iran Server
# ════════════════════════════════════════════════════════
setup_iran() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═════════════════════════════════════════════════════╗"
    echo "  ║       AilyTunnel v${VERSION} — Iran Server Setup        ║"
    echo "  ╚═════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local PUBLIC_IP; PUBLIC_IP=$(get_ip)
    info "Public IP: ${BOLD}${PUBLIC_IP}${NC}"; echo ""

    while true; do
        ask "Control port [default: 2333]:"; read -r CTRL; CTRL=${CTRL:-2333}
        valid_port "$CTRL" && break || fail "Invalid port"
    done

    local AUTO; AUTO=$(gen_token)
    ask "Security token [Enter = auto-generate]:"; read -r TOKEN; TOKEN=${TOKEN:-$AUTO}

    ask "Connection pool size [default: 16]:"; read -r POOL; POOL=${POOL:-16}
    [[ "$POOL" =~ ^[0-9]+$ ]] || POOL=16

    ask "Prometheus metrics port [default: 9090, 0=disabled]:"
    read -r MPORT; MPORT=${MPORT:-9090}
    local METRICS_ADDR=""
    [[ "$MPORT" != "0" ]] && METRICS_ADDR="127.0.0.1:${MPORT}"

    select_transport
    [[ "$USE_TLS_CERT" == "1" ]] && gen_tls_cert "$CFG_DIR"

    select_protocols iran
    build_service_entries "$TOKEN" iran
    [[ -z "$SVC_BLOCK" ]] && die "No services configured"

    echo ""
    echo -e "${YELLOW}── Summary ──────────────────────────────────────────${NC}"
    echo -e "  Public IP   : ${GREEN}${PUBLIC_IP}${NC}"
    echo -e "  Control     : ${GREEN}${CTRL}/${TRANSPORT}${NC}"
    echo -e "  Token       : ${GREEN}${TOKEN}${NC}"
    echo -e "  Pool        : ${GREEN}${POOL}${NC}"
    [[ -n "$METRICS_ADDR" ]] && echo -e "  Metrics     : ${GREEN}${METRICS_ADDR}/metrics${NC}"
    [[ "$TRANSPORT" == "kcp" || "$TRANSPORT" == "multipath" ]] && \
        echo -e "  KCP         : ${MAGENTA}${KCP_MODE} FEC(${DS}+${PS}) ${KCP_CRYPT} DSCP=46${NC}"
    echo ""
    ask "Continue? [Y/n]:"; read -r C; [[ "${C,,}" == "n" ]] && { warn "Aborted"; exit 0; }

    install_deps
    install_go
    build

    step "Writing server config"
    mkdir -p "$CFG_DIR"
    local TRANSPORT_BLOCK; TRANSPORT_BLOCK=$(build_transport_block "$TOKEN" server)
    local METRICS_LINE=""
    [[ -n "$METRICS_ADDR" ]] && METRICS_LINE="metrics_addr = \"${METRICS_ADDR}\""

    cat > "${CFG_DIR}/server.toml" << EOF
# AilyTunnel v${VERSION} — Server (Iran)
# Generated: $(date)
# Hot reload: systemctl reload ${SVC}

[server]
bind_addr = "0.0.0.0:${CTRL}"
default_token = "${TOKEN}"
heartbeat_interval = 30
${METRICS_LINE}
${TRANSPORT_BLOCK}
${SVC_BLOCK}
EOF
    ok "Config: ${CFG_DIR}/server.toml"

    step "Opening firewall ports"
    open_port "$CTRL" tcp
    [[ "$TRANSPORT" == "kcp" || "$TRANSPORT" == "multipath" ]] && open_port "$CTRL" udp
    for PT in "${PORTS_TO_OPEN[@]}"; do
        open_port "${PT%%:*}" "${PT##*:}"
    done
    if [[ "$TRANSPORT" == "multipath" && -n "${EXTRA_PORTS:-}" ]]; then
        for EP in $EXTRA_PORTS; do open_port "$EP" udp; done
    fi

    step "Starting service"
    create_service "server" "${CFG_DIR}/server.toml"
    start_service
    sleep 2

    if systemctl is-active --quiet "$SVC" 2>/dev/null || \
       "/etc/init.d/${SVC}" status 2>/dev/null | grep -q running; then
        ok "AilyTunnel server running!"
    else
        fail "Service failed to start"
        journalctl -u "$SVC" -n 20 --no-pager 2>/dev/null || \
            cat /var/log/syslog 2>/dev/null | tail -20 || true
        exit 1
    fi

    # Save info for foreign server
    {
        echo "IRAN_IP=${PUBLIC_IP}"
        echo "CTRL=${CTRL}"
        echo "TOKEN=${TOKEN}"
        echo "POOL=${POOL}"
        echo "TRANSPORT=${TRANSPORT}"
        [[ "$TRANSPORT" == "kcp" || "$TRANSPORT" == "multipath" ]] && {
            echo "KCP_MODE=${KCP_MODE}"
            echo "KCP_CRYPT=${KCP_CRYPT}"
            echo "KCP_DS=${DS:-10}"
            echo "KCP_PS=${PS:-3}"
        }
        [[ "$TRANSPORT" == "multipath" && -n "${EXTRA_PORTS:-}" ]] && \
            echo "EXTRA_PORTS=${EXTRA_PORTS}"
    } > "${CFG_DIR}/iran_info.txt"
    printf "%b" "$CLIENT_SVCS" > "${CFG_DIR}/iran_svcs.txt"

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║              Iran server is ready!                   ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}  Copy these to Foreign server setup:${NC}"
    echo -e "  ┌──────────────────────────────────────────────────────"
    echo -e "  │  IP        : ${GREEN}${PUBLIC_IP}${NC}"
    echo -e "  │  Port      : ${GREEN}${CTRL}${NC}"
    echo -e "  │  Token     : ${GREEN}${TOKEN}${NC}"
    echo -e "  │  Transport : ${GREEN}${TRANSPORT}${NC}"
    [[ "$TRANSPORT" == "kcp" || "$TRANSPORT" == "multipath" ]] && \
        echo -e "  │  KCP       : ${MAGENTA}${KCP_MODE} | FEC ${DS}+${PS} | ${KCP_CRYPT}${NC}"
    echo -e "  └──────────────────────────────────────────────────────"
    echo ""
    echo -e "${CYAN}  Commands:${NC}"
    echo -e "  Status     : systemctl status ${SVC}"
    echo -e "  Logs       : journalctl -u ${SVC} -f"
    echo -e "  Hot reload : systemctl reload ${SVC}"
    echo -e "  Config     : cat ${CFG_DIR}/server.toml"
    [[ -n "$METRICS_ADDR" ]] && \
        echo -e "  Metrics    : curl -s http://${METRICS_ADDR}/metrics"
}

# ════════════════════════════════════════════════════════
# SETUP: Foreign Server
# ════════════════════════════════════════════════════════
setup_foreign() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═════════════════════════════════════════════════════╗"
    echo "  ║     AilyTunnel v${VERSION} — Foreign Server Setup       ║"
    echo "  ╚═════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Auto-load from previous Iran setup
    PRELOAD_IP=""; PRELOAD_CTRL="2333"; PRELOAD_TOKEN=""
    PRELOAD_POOL="16"; PRELOAD_TRANSPORT="tcp"
    if [[ -f "${CFG_DIR}/iran_info.txt" ]]; then
        info "Loading Iran server info..."
        # shellcheck disable=SC1090
        . "${CFG_DIR}/iran_info.txt" 2>/dev/null || true
        PRELOAD_IP="${IRAN_IP:-}"; PRELOAD_CTRL="${CTRL:-2333}"
        PRELOAD_TOKEN="${TOKEN:-}"; PRELOAD_POOL="${POOL:-16}"
        PRELOAD_TRANSPORT="${TRANSPORT:-tcp}"
        if [[ "$PRELOAD_TRANSPORT" == "kcp" || "$PRELOAD_TRANSPORT" == "multipath" ]]; then
            KCP_MODE="${KCP_MODE:-fast3}"; KCP_CRYPT="${KCP_CRYPT:-aes-128}"
            DS="${KCP_DS:-10}"; PS="${KCP_PS:-3}"
            EXTRA_PORTS="${EXTRA_PORTS:-}"
        fi
        TRANSPORT="$PRELOAD_TRANSPORT"
        [[ "$PRELOAD_TRANSPORT" == "tls" ]] && USE_TLS_CERT=1 || USE_TLS_CERT=0
    fi

    ask "Iran server IP [${PRELOAD_IP:-required}]:"; read -r IRAN_IP
    IRAN_IP="${IRAN_IP:-${PRELOAD_IP:-}}"
    [[ -n "$IRAN_IP" ]] || die "Iran IP required"

    ask "Control port [${PRELOAD_CTRL}]:"; read -r CTRL; CTRL="${CTRL:-$PRELOAD_CTRL}"
    ask "Token [${PRELOAD_TOKEN:-required}]:"; read -r TOKEN; TOKEN="${TOKEN:-${PRELOAD_TOKEN:-}}"
    [[ -n "$TOKEN" ]] || die "Token required"
    ask "Pool size [${PRELOAD_POOL}]:"; read -r POOL; POOL="${POOL:-$PRELOAD_POOL}"
    [[ "$POOL" =~ ^[0-9]+$ ]] || POOL=16

    ask "Use same transport as Iran? (${PRELOAD_TRANSPORT}) [Y/n]:"; read -r SAME
    [[ "${SAME,,}" == "n" ]] && select_transport

    # Services
    if [[ -f "${CFG_DIR}/iran_svcs.txt" ]]; then
        info "Loading services from Iran setup..."
        SVC_BLOCK=""
        while IFS=':' read -r NAME TYPE CP PRIO BW; do
            [[ -z "$NAME" ]] && continue
            ask "Local address for ${NAME} (${TYPE}) [default: 127.0.0.1:${CP}]:"
            read -r LOCAL; LOCAL="${LOCAL:-127.0.0.1:${CP}}"
            SVC_BLOCK+="
[client.services.${NAME}]
type = \"${TYPE}\"
token = \"${TOKEN}\"
local_addr = \"${LOCAL}\"
nodelay = true
priority = \"${PRIO:-normal}\"
bandwidth_mbps = ${BW:-0}
"
            ok "Added ${NAME} → ${LOCAL}"
        done < "${CFG_DIR}/iran_svcs.txt"
    else
        select_protocols foreign
        build_service_entries "$TOKEN" foreign
    fi

    [[ -z "$SVC_BLOCK" ]] && die "No services configured"

    ask "Continue? [Y/n]:"; read -r C; [[ "${C,,}" == "n" ]] && { warn "Aborted"; exit 0; }

    install_deps
    install_go
    build

    step "Writing client config"
    mkdir -p "$CFG_DIR"
    local TRANSPORT_BLOCK; TRANSPORT_BLOCK=$(build_transport_block "$TOKEN" client)

    cat > "${CFG_DIR}/client.toml" << EOF
# AilyTunnel v${VERSION} — Client (Foreign)
# Generated: $(date)

[client]
remote_addr = "${IRAN_IP}:${CTRL}"
default_token = "${TOKEN}"
heartbeat_timeout = 40
retry_interval = 3
pool_size = ${POOL}
${TRANSPORT_BLOCK}
${SVC_BLOCK}
EOF
    ok "Config: ${CFG_DIR}/client.toml"

    step "Starting service"
    create_service "client" "${CFG_DIR}/client.toml"
    start_service
    sleep 3

    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        ok "AilyTunnel client running!"
    else
        fail "Service failed"
        journalctl -u "$SVC" -n 20 --no-pager 2>/dev/null || true
        exit 1
    fi

    step "Testing connection to Iran"
    if timeout 5 bash -c "echo >/dev/tcp/${IRAN_IP}/${CTRL}" 2>/dev/null; then
        ok "Connection to ${IRAN_IP}:${CTRL} verified"
    else
        warn "TCP test failed — if using KCP(UDP) this is expected"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║            Foreign server is ready!                  ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}  x-ui inbound — Listen IP MUST be 127.0.0.1:${NC}"
    grep "local_addr" "${CFG_DIR}/client.toml" | while read -r LINE; do
        PORT=$(echo "$LINE" | grep -oP ':\K[0-9]+$')
        echo -e "    127.0.0.1:${PORT}"
    done
    echo ""
    echo -e "${CYAN}  Commands:${NC}"
    echo -e "  Status     : systemctl status ${SVC}"
    echo -e "  Logs       : journalctl -u ${SVC} -f"
    echo -e "  Hot reload : systemctl reload ${SVC}"
}

# ════════════════════════════════════════════════════════
# Kernel tuning
# ════════════════════════════════════════════════════════
tune_kernel() {
    step "Applying kernel + QoS optimizations"
    modprobe tcp_bbr 2>/dev/null || true

    cat > /etc/sysctl.d/99-ailytunnel.conf << 'EOF'
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.rmem_default = 26214400
net.core.wmem_default = 26214400
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_no_metrics_save = 1
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 32768
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.ip_forward = 1
EOF
    sysctl -p /etc/sysctl.d/99-ailytunnel.conf &>/dev/null || true

    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        ok "BBR active"
    else
        warn "BBR not available on this kernel"
    fi

    local IFACE; IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
    if [[ -n "${IFACE:-}" ]]; then
        tc qdisc del dev "$IFACE" root 2>/dev/null || true
        tc qdisc add dev "$IFACE" root handle 1: prio bands 3 \
            priomap 0 0 0 0 1 1 1 1 1 2 2 2 2 2 2 2 2>/dev/null || true
        tc filter add dev "$IFACE" parent 1: protocol ip u32 \
            match ip dsfield 0xb8 0xfc flowid 1:1 2>/dev/null || true
        ok "QoS applied on ${IFACE}"
    fi
    ok "Kernel optimization complete"
}

# ════════════════════════════════════════════════════════
# Manage
# ════════════════════════════════════════════════════════
manage() {
    clear
    echo -e "${BOLD}${CYAN}  AilyTunnel v${VERSION} — Manage${NC}\n"
    local ST; ST=$(systemctl is-active "$SVC" 2>/dev/null || echo "inactive")
    [[ "$ST" == "active" ]] \
        && echo -e "  Status : ${GREEN}● running${NC}" \
        || echo -e "  Status : ${RED}● stopped${NC}"
    echo ""
    echo "  1) Status"
    echo "  2) Live logs"
    echo "  3) Restart"
    echo "  4) Stop / Start"
    echo "  5) Hot reload (no downtime)"
    echo "  6) Show config"
    echo "  7) Add service"
    echo "  8) Active connections"
    echo "  9) Rebuild binary"
    echo " 10) Uninstall"
    echo "  0) Exit"
    echo ""
    ask "Choice:"; read -r C
    case "$C" in
        1) systemctl status "$SVC" ;;
        2) journalctl -u "$SVC" -f ;;
        3) systemctl restart "$SVC" && ok "Restarted" ;;
        4) [[ "$ST" == "active" ]] \
            && { systemctl stop "$SVC" && ok "Stopped"; } \
            || { systemctl start "$SVC" && ok "Started"; } ;;
        5) systemctl reload "$SVC" && ok "Hot reloaded" ;;
        6) for f in "${CFG_DIR}/server.toml" "${CFG_DIR}/client.toml"; do
               [[ -f "$f" ]] && { echo ""; cat "$f"; break; }
           done ;;
        7) add_service ;;
        8) ss -tupn 2>/dev/null | grep ailytunnel || echo "No connections" ;;
        9)
            info "Rebuilding binary..."
            install_go
            force_build
            systemctl restart "$SVC" 2>/dev/null && ok "Restarted with new binary"
            ;;
        10)
            ask "Uninstall everything? [y/N]:"; read -r Y
            [[ "${Y,,}" == "y" ]] && {
                systemctl stop "$SVC" 2>/dev/null || true
                systemctl disable "$SVC" 2>/dev/null || true
                rm -f "/etc/systemd/system/${SVC}.service" "$BINARY"
                rm -rf "$CFG_DIR"
                systemctl daemon-reload 2>/dev/null || true
                ok "Uninstalled"
            } ;;
        0) exit 0 ;;
    esac
}

add_service() {
    local CFGFILE=""
    [[ -f "${CFG_DIR}/server.toml" ]] && CFGFILE="${CFG_DIR}/server.toml"
    [[ -f "${CFG_DIR}/client.toml" ]] && CFGFILE="${CFG_DIR}/client.toml"
    [[ -z "$CFGFILE" ]] && { fail "No config found"; return; }
    local MODE="client"; [[ "$CFGFILE" == *"server"* ]] && MODE="server"
    local TOK; TOK=$(grep default_token "$CFGFILE" | awk -F'"' '{print $2}')

    ask "Service name:"; read -r NAME; [[ -z "$NAME" ]] && return
    ask "Type [tcp/udp]:"; read -r TYPE; TYPE=${TYPE:-tcp}
    ask "Priority [high/normal/low]:"; read -r PRIO; PRIO=${PRIO:-normal}

    if [[ "$MODE" == "server" ]]; then
        ask "Bind address (e.g. 0.0.0.0:9000):"; read -r ADDR
        cat >> "$CFGFILE" << EOF

[server.services.${NAME}]
type = "${TYPE}"
token = "${TOK}"
bind_addr = "${ADDR}"
nodelay = true
priority = "${PRIO}"
max_conn_rate = 100
bandwidth_mbps = 0
ip_whitelist = []
ip_blacklist = []
EOF
        open_port "${ADDR##*:}" "$TYPE"
    else
        ask "Local address (e.g. 127.0.0.1:9000):"; read -r ADDR
        cat >> "$CFGFILE" << EOF

[client.services.${NAME}]
type = "${TYPE}"
token = "${TOK}"
local_addr = "${ADDR}"
nodelay = true
priority = "${PRIO}"
bandwidth_mbps = 0
EOF
    fi
    systemctl reload "$SVC" 2>/dev/null || systemctl restart "$SVC"
    ok "Service '${NAME}' added"
}

# ════════════════════════════════════════════════════════
# Main menu
# ════════════════════════════════════════════════════════
main() {
    detect_os
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═════════════════════════════════════════════════════════════╗"
    echo "  ║                                                             ║"
    echo "  ║            AilyTunnel Setup v${VERSION}                         ║"
    echo "  ║                                                             ║"
    echo "  ║  Auto-installs Go · Builds binary · Configures service     ║"
    echo "  ║  Works on Ubuntu · Debian · CentOS · Rocky · Any Linux     ║"
    echo "  ║                                                             ║"
    echo "  ║  TCP · TLS · KCP+FEC · WebSocket · Multipath               ║"
    echo "  ║  IP ACL · Rate Limit · Throttle · Hot Reload · Metrics     ║"
    echo "  ║                                                             ║"
    echo "  ╚═════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # If already installed, show manage menu first
    if systemctl list-unit-files "${SVC}.service" &>/dev/null 2>&1 \
       && systemctl is-enabled "$SVC" &>/dev/null 2>&1; then
        local ST; ST=$(systemctl is-active "$SVC" 2>/dev/null || echo "inactive")
        [[ "$ST" == "active" ]] \
            && echo -e "  Existing: ${GREEN}● running${NC}" \
            || echo -e "  Existing: ${RED}● stopped${NC}"
        echo ""
        echo "  1) Manage"
        echo "  2) Reinstall / reconfigure"
        echo "  3) Rebuild binary only"
        echo "  4) Kernel + QoS optimizations"
        echo "  0) Exit"
        echo ""
        ask "Choice:"; read -r I
        case "$I" in
            1) manage; exit 0 ;;
            2) : ;;
            3) install_go; force_build
               systemctl restart "$SVC" 2>/dev/null && ok "Restarted"
               exit 0 ;;
            4) tune_kernel; exit 0 ;;
            0) exit 0 ;;
        esac
        echo ""
    fi

    echo -e "  ${BOLD}Which server is this?${NC}"
    echo ""
    echo "  1) Iran server    — public IP, users connect here"
    echo "  2) Foreign server — x-ui/xray is here"
    echo "  3) Kernel + QoS   — run once on BOTH servers"
    echo "  0) Exit"
    echo ""
    ask "Choice:"; read -r CHOICE
    case "$CHOICE" in
        1) setup_iran ;;
        2) setup_foreign ;;
        3) tune_kernel ;;
        0) echo "Bye!"; exit 0 ;;
        *) fail "Invalid"; exit 1 ;;
    esac
}

main