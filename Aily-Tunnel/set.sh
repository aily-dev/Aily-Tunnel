#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-install.sh}"

if [[ ! -f "$TARGET" ]]; then
  echo "[-] File not found: $TARGET"
  echo "Usage: $0 /path/to/install.sh"
  exit 1
fi

cp -a "$TARGET" "${TARGET}.bak.$(date +%Y%m%d_%H%M%S)"

python3 - "$TARGET" <<'PY'
import re
import sys
from pathlib import Path

target = Path(sys.argv[1])
text = target.read_text(encoding="utf-8", errors="ignore")

install_binary_only_func = r'''
install_binary_only() {
    step "Installing AilyTunnel binary"

    local SDIR
    SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    local SRC_BIN=""
    if [[ -x "$SDIR/ailytunnel" ]]; then
        SRC_BIN="$SDIR/ailytunnel"
        info "Found binary in: ${SDIR}"
    elif [[ -x "$BINARY" ]]; then
        SRC_BIN="$BINARY"
        info "Using existing installed binary: ${BINARY}"
    else
        fail "Prebuilt binary not found!"
        info "Expected one of these:"
        info "  ${SDIR}/ailytunnel"
        info "  ${BINARY}"
        die "Put a ready-made 'ailytunnel' binary next to this script and retry"
    fi

    if pgrep -x ailytunnel >/dev/null 2>&1; then
        warn "Stopping running ailytunnel processes to avoid 'Text file busy'..."
        pkill -x ailytunnel 2>/dev/null || true
        sleep 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$SVC" 2>/dev/null; then
            warn "Stopping ${SVC} service temporarily..."
            systemctl stop "$SVC" 2>/dev/null || true
            sleep 1
        fi
    fi

    info "Installing binary to ${BINARY} ..."
    install -m 0755 "$SRC_BIN" "${BINARY}.new"
    mv -f "${BINARY}.new" "$BINARY"
    chmod +x "$BINARY"

    if [[ ! -x "$BINARY" ]]; then
        die "Binary installation failed"
    fi

    echo ""
    echo -e "${CYAN}── Binary info ──────────────────────────${NC}"
    "$BINARY" --help 2>&1 | head -5 || true
    echo -e "${CYAN}─────────────────────────────────────────${NC}"
    echo ""

    ok "AilyTunnel binary installed → ${BINARY}"
}
'''.strip("\n")

force_build_func = r'''
force_build() {
    rm -f "$BINARY"
    install_binary_only
}
'''.strip("\n")

def replace_function(src: str, func_name: str, new_body: str):
    pattern = re.compile(
        rf'(^[ \t]*{re.escape(func_name)}\(\)[ \t]*\{{\n)'
        rf'(.*?)'
        rf'(^\}}[ \t]*\n)',
        re.M | re.S
    )
    if pattern.search(src):
        src = pattern.sub(new_body + "\n", src, count=1)
        return src, True
    return src, False

# 1) build() -> install_binary_only()
text, build_found = replace_function(text, "build", install_binary_only_func)

# اگر build() پیدا نشد ولی install_binary_only هم نیست، تابع را قبل از main اضافه کن
if not build_found and "install_binary_only()" not in text:
    m = re.search(r'^[ \t]*main\(\)[ \t]*\{', text, re.M)
    if m:
        text = text[:m.start()] + install_binary_only_func + "\n\n" + text[m.start():]
    else:
        text += "\n\n" + install_binary_only_func + "\n"

# 2) force_build() -> reinstall binary only
text, force_found = replace_function(text, "force_build", force_build_func)
if not force_found and "force_build()" not in text:
    m = re.search(r'^[ \t]*main\(\)[ \t]*\{', text, re.M)
    if m:
        text = text[:m.start()] + "\n" + force_build_func + "\n\n" + text[m.start():]
    else:
        text += "\n\n" + force_build_func + "\n"

# 3) setup_* call sites: install_go + build  => install_binary_only
text = re.sub(
    r'^[ \t]*install_go[ \t]*\n[ \t]*build[ \t]*$',
    '    install_binary_only',
    text,
    flags=re.M
)

# 4) اگر جایی فقط build تنها صدا شده
text = re.sub(
    r'(?m)^([ \t]*)build([ \t]*)$',
    r'\1install_binary_only\2',
    text
)

# 5) مدیریت rebuild
text = re.sub(
    r'^[ \t]*info "Rebuilding binary\.\.\."[ \t]*\n[ \t]*install_go[ \t]*\n[ \t]*force_build[ \t]*$',
    '            info "Reinstalling binary..."\n            force_build',
    text,
    flags=re.M
)

# 6) گزینه منو که install_go; force_build دارد
text = re.sub(
    r'(?m)^([ \t]*3\)[ \t]*)install_go;[ \t]*force_build([ \t]*)$',
    r'\1force_build\2',
    text
)

# 7) اگر install_go فقط برای build استفاده می‌شد، لازم نیست حذفش کنیم.
# بقیه مراحل دست‌نخورده می‌مانند.

target.write_text(text, encoding="utf-8")
print(f"[+] Patched successfully: {target}")
PY

echo "[+] Done."
echo "[+] Backup created next to original file."
echo "[+] Now make sure a prebuilt binary named 'ailytunnel' is next to install.sh"
echo "[+] Then run:"
echo "    chmod +x \"$TARGET\""
echo "    sudo ./$(basename "$TARGET")"
