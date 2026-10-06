#!/usr/bin/env bash
# AXIOM CHAIN installer — macOS + Linux port (by CY3ER-CAT)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.axiom"
PLATFORM="$(uname -s)"

log() { printf '[\e[32mCY3ER-CAT\e[0m] %s\n' "$*"; }
die() { printf '[\e[31mCY3ER-CAT\e[0m] %s\n' "$*" >&2; exit 1; }

# --- 1. dependency check ---
log "Checking dependencies..."
missing=0
for bin in tor curl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        printf '  missing: %s\n' "$bin"
        missing=1
    fi
done
if [[ $missing -eq 1 ]]; then
    if [[ "$PLATFORM" == Darwin ]]; then
        die "Install missing deps first: brew install tor curl"
    elif [[ "$PLATFORM" == MINGW* || "$PLATFORM" == MSYS* || "$PLATFORM" == CYGWIN* ]]; then
        die "Install missing deps first: put tor.exe and curl.exe on PATH (Tor Expert Bundle)"
    else
        die "Install missing deps first: sudo apt install tor curl"
    fi
fi
log "All required deps present."

if command -v proxychains4 >/dev/null 2>&1; then
    log "proxychains4 found -> kernel proxy mode enabled."
elif [[ "$PLATFORM" == Darwin ]]; then
    log "NOTE: no proxychains4. macOS SIP strips DYLD_INSERT_LIBRARIES from /bin/bash and"
    log "      /usr/bin/*, so a kernel tunnel is not honestly achievable here."
    log "      Falling back to per-tool SOCKS env routing (curl/git/npm/wget obey it)."
elif [[ "$PLATFORM" == MINGW* || "$PLATFORM" == MSYS* || "$PLATFORM" == CYGWIN* ]]; then
    log "NOTE: Windows/Git Bash. No proxychains4 exists for Windows -> per-tool SOCKS env mode."
    log "      Need tor.exe and curl.exe on PATH (Tor Expert Bundle ships both)."
    log "      For a real full tunnel on Windows, run this inside WSL instead."
else
    log "NOTE: no proxychains4 -> per-tool SOCKS env routing. Install proxychains for kernel mode."
fi

# --- 2. syntax check before touching $HOME ---
log "Syntax-checking scripts..."
for f in axiom-lib.sh axiom-menu.sh axiom-multihop.sh; do
    bash -n "$SRC/$f" || die "syntax error in $f"
    log "  ok: $f"
done

# --- 3. copy files ---
log "Installing to $DEST ..."
mkdir -p "$DEST"
install -m 755 "$SRC/axiom-lib.sh" "$SRC/axiom-menu.sh" "$SRC/axiom-multihop.sh" "$DEST/"
install -m 644 "$SRC/proxychains4.conf" "$DEST/"
log "Scripts installed."

# --- 4. shell auto-boot (zsh + bash) ---
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
    _axm_key="\${AXIOM_SESSION_KEY:-\${XDG_SESSION_ID:-\$\$}}"
    _axm_marker="/tmp/.axiom-booted-\${_axm_key}"
    if [[ ! -f "\$_axm_marker" ]]; then
        touch "\$_axm_marker" 2>/dev/null
        "\$HOME/.axiom/axiom-menu.sh" 2>/dev/null || true
    fi
    unset _axm_key _axm_marker
fi
EOF
    log "Auto-boot wired in $rc"
}
wire_rc "$HOME/.zshrc" "[[ -o interactive ]]"
wire_rc "$HOME/.bashrc" '[[ $- == *i* ]]'

# --- 5. launcher ---
if [[ "$PLATFORM" == Darwin ]]; then
    if [[ -d "$HOME/Desktop" ]]; then
        log "Creating Desktop launcher..."
        cat > "$HOME/Desktop/AXIOM-Connect.command" << EOF
#!/bin/bash
# AXIOM Connect — double-click to open the chain menu.
exec "$DEST/axiom-menu.sh"
EOF
        chmod +x "$HOME/Desktop/AXIOM-Connect.command"
        xattr -d com.apple.quarantine "$HOME/Desktop/AXIOM-Connect.command" 2>/dev/null || true
        log "Launcher installed: ~/Desktop/AXIOM-Connect.command"
    else
        log "No ~/Desktop — skipped launcher (use: axiom)"
    fi
elif [[ "$PLATFORM" == MINGW* || "$PLATFORM" == MSYS* || "$PLATFORM" == CYGWIN* ]]; then
    WINHOME="${USERPROFILE:-$HOME}"
    if [[ -d "$WINHOME/Desktop" ]]; then
        log "Creating Desktop launcher..."
        cat > "$WINHOME/Desktop/AXIOM-Connect.cmd" << EOF
@echo off
bash "$DEST/axiom-menu.sh"
pause
EOF
        log "Launcher installed: $WINHOME/Desktop/AXIOM-Connect.cmd"
    else
        log "No Desktop folder — skipped launcher (run: axiom)"
    fi
else
    log "Creating desktop shortcut..."
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
fi

echo ""
log "INSTALL COMPLETE — by CY3ER-CAT"
echo "  connect  : double-click AXIOM-Connect, or type: axiom"
echo "  skip auto-boot once : AXIOM_NO_MENU=1 axiom"
echo "  disconnect: exit (shell)  ->  8 (menu)"