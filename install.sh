#!/usr/bin/env bash
# AXIOM CHAIN installer — by CY3ER-CAT
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.axiom"
MENU="$DEST/axiom-menu.sh"

log()  { printf '[\e[32mCY3ER-CAT\e[0m] %s\n' "$*"; }
die()  { printf '[\e[31mCY3ER-CAT\e[0m] %s\n' "$*" >&2; exit 1; }

# --- 1. dependency check ---
log "Checking dependencies..."
missing=0
for bin in tor proxychains4 curl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        printf '  missing: %s\n' "$bin"
        missing=1
    fi
done
if [[ $missing -eq 1 ]]; then
    die "Install missing deps first: sudo apt install tor proxychains4 curl"
fi
log "All deps present."

# --- 2. copy files ---
log "Installing to $DEST ..."
mkdir -p "$DEST"
install -m 755 "$SRC/axiom-menu.sh" "$SRC/axiom-multihop.sh" "$DEST/"
install -m 644 "$SRC/proxychains4.conf" "$DEST/"
log "Scripts installed."

# --- 3. shell auto-boot (zsh + bash) ---
wire_rc() {
    local rc="$1" interactive_test="$2"
    [[ -f "$rc" ]] || return 0
    if grep -q "axiom home screen" "$rc" 2>/dev/null; then
        log "Auto-boot already wired in $rc"
        return 0
    fi
    cat >> "$rc" << EOF

# --- axiom home screen (CY3ER-CAT) : auto-on at login, off when menu closes ---
alias axiom="\$HOME/.axiom/axiom-menu.sh"
if $interactive_test && [[ -z "\${AXIOM_IN_MENU:-}" && -z "\${AXIOM_NO_MENU:-}" ]]; then
    _axm_marker="/tmp/.axiom-booted-\${XDG_SESSION_ID:-\$\$}"
    if [[ ! -f "\$_axm_marker" ]]; then
        touch "\$_axm_marker" 2>/dev/null
        "\$HOME/.axiom/axiom-menu.sh" 2>/dev/null || true
    fi
    unset _axm_marker
fi
EOF
    log "Auto-boot wired in $rc"
}
wire_rc "$HOME/.zshrc" "[[ -o interactive ]]"
wire_rc "$HOME/.bashrc" '[[ $- == *i* ]]'

# --- 4. desktop shortcut ---
log "Creating desktop launcher..."
ICON=$(find /usr/share/icons -name "nm-vpn-standalone-lock.svg" 2>/dev/null | head -1)
ICON="${ICON:-/usr/share/icons/Flat-Remix-Blue-Light/panel/network-transmit-receive.svg}"
TERM_BIN=$(command -v xfce4-terminal || command -v x-terminal-emulator || command -v gnome-terminal || true)
if [[ -n "$TERM_BIN" ]]; then
    mkdir -p "$HOME/.local/share/applications" "$HOME/Desktop"
    for dest in "$HOME/Desktop/AXIOM-Connect.desktop" "$HOME/.local/share/applications/axiom-connect.desktop"; do
        cat > "$dest" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=AXIOM Connect
GenericName=Proxy Chain Launcher
Comment=Click to connect the multi-hop chain — close menu to disconnect
Exec=$TERM_BIN -T "AXIOM CHAIN" -e "bash -lc '$DEST/axiom-menu.sh'"
Icon=$ICON
Terminal=false
Categories=Network;Security;System;
StartupNotify=false
EOF
        chmod +x "$dest"
    done
    log "Shortcut installed: ~/Desktop/AXIOM-Connect.desktop"
else
    log "No terminal emulator found — skipped desktop shortcut (use: axiom)"
fi

echo ""
log "INSTALL COMPLETE — by CY3ER-CAT"
echo "  connect  : click AXIOM-Connect, or type: axiom"
echo "  disconnect: exit  (shell)  ->  8  (menu)"
