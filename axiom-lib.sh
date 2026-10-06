#!/usr/bin/env bash
# axiom-lib.sh — shared platform helpers (macOS + Linux + Git Bash/MSYS2)
# Sourced by axiom-menu.sh and axiom-multihop.sh. Safe under `set -euo pipefail`.
#
# Platform support:
#   macos    — Darwin, native
#   linux    — Linux, Kali, and WSL (uname -s is "Linux", so WSL is covered natively)
#   windows  — Git Bash / MSYS2 / Cygwin. EXPERIMENTAL: needs tor.exe + curl.exe
#              on PATH. No proxychains4 exists for Windows, so proxy mode is
#              always "env" there.

AXIOM_BASE="${AXIOM_BASE:-$HOME/.axiom}"
AXIOM_TOR_DATA="$AXIOM_BASE/tor-data"
AXIOM_PORTS_FILE="$AXIOM_BASE/tor.ports"
AXIOM_SOCKS_PORT_DEFAULT=9050
AXIOM_CTRL_PORT_DEFAULT=9051

axiom_log() { printf '[\e[35mAXIOM\e[0m] %s\n' "$*"; }
axiom_err() { printf '[\e[31mAXIOM\e[0m] %s\n' "$*" >&2; }

axiom_platform() {
    case "$(uname -s)" in
        Darwin)          echo macos ;;
        Linux)           echo linux ;;
        MINGW*|MSYS*|CYGWIN*) echo windows ;;
        *)               echo unknown ;;
    esac
}

axiom_is_windows() { [[ "$(axiom_platform)" == windows ]]; }

# --- ports -----------------------------------------------------------------

axiom_socks_port() {
    if [[ -r "$AXIOM_PORTS_FILE" ]]; then cut -d' ' -f1 "$AXIOM_PORTS_FILE"
    else echo "$AXIOM_SOCKS_PORT_DEFAULT"; fi
}

axiom_ctrl_port() {
    if [[ -r "$AXIOM_PORTS_FILE" ]]; then cut -d' ' -f2 "$AXIOM_PORTS_FILE"
    else echo "$AXIOM_CTRL_PORT_DEFAULT"; fi
}

port_free() {
    if axiom_is_windows; then
        # MSYS path-mangles a leading slash, hence the doubled one.
        ! netstat -ano 2>/dev/null | grep -qE "[:.]${1}[[:space:]].*LISTENING"
        return
    fi
    if command -v lsof >/dev/null 2>&1; then
        ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
    elif command -v nc >/dev/null 2>&1; then
        ! nc -z 127.0.0.1 "$1" >/dev/null 2>&1
    else
        return 0
    fi
}

# --- timeouts (macOS and Git Bash have no coreutils `timeout`) -------------

axiom_timeout_bin() {
    if command -v timeout >/dev/null 2>&1; then echo timeout
    elif command -v gtimeout >/dev/null 2>&1; then echo gtimeout
    else echo ""; fi
}

# --- process helpers -------------------------------------------------------
# Git Bash ships neither pgrep/pkill nor lsof, so every process lookup in the
# stack routes through these instead of calling the tools directly.

# axiom_pids <exact-name> -> PIDs, one per line
axiom_pids() {
    if axiom_is_windows; then
        local img; img="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]').EXE"
        tasklist //FI "IMAGENAME eq $img" //NH 2>/dev/null \
            | awk -v n="$img" 'toupper($1) == n { gsub(/\r/, "", $2); print $2 }'
    else
        pgrep -x "$1" 2>/dev/null || true
    fi
}

axiom_pid_alive() {
    if axiom_is_windows; then
        tasklist //FI "PID eq $1" //NH 2>/dev/null | grep -qE "^${1}[[:space:]]"
    else
        kill -0 "$1" 2>/dev/null
    fi
}

axiom_kill_tree() {
    local pid="${1:-}" sig="${2:-TERM}"
    [[ -n "$pid" ]] || return 0
    if axiom_is_windows; then
        taskkill //PID "$pid" //T //F >/dev/null 2>&1 || true
    else
        pkill "-$sig" -P "$pid" 2>/dev/null || true
        kill "-$sig" "$pid" 2>/dev/null || true
    fi
    return 0
}

axiom_kill() {
    local pid="${1:-}" sig="${2:-TERM}"
    [[ -n "$pid" ]] || return 0
    if axiom_is_windows; then
        taskkill //PID "$pid" //F >/dev/null 2>&1 || true
    else
        kill "-$sig" "$pid" 2>/dev/null || true
    fi
    return 0
}

# Is this PID our Tor? Linux/macOS match the DataDirectory; on Windows there is
# no lsof, so we match whoever owns our SOCKS port instead.
axiom_pid_is_tor() {
    local pid="${1:-}" socks
    socks=$(axiom_socks_port)
    if axiom_is_windows; then
        netstat -ano 2>/dev/null \
            | grep -E "[:.]${socks}[[:space:]].*LISTENING" \
            | grep -qE "[[:space:]]${pid}[[:space:]]*$"
    else
        lsof -nP -p "$pid" 2>/dev/null | grep -q "$AXIOM_TOR_DATA"
    fi
}

axiom_tor_pid() {
    local p
    for p in $(axiom_pids tor); do
        if axiom_pid_is_tor "$p"; then echo "$p"; return 0; fi
    done
    return 1
}

# --- network interfaces ----------------------------------------------------

iface_exists() {
    case "$(axiom_platform)" in
        macos)   ifconfig "$1" >/dev/null 2>&1 ;;
        windows) return 1 ;;   # no tun-style ifaces; see axiom_vpn_supported
        *)       ip link show "$1" >/dev/null 2>&1 ;;
    esac
}

iface_ipv4() {
    case "$(axiom_platform)" in
        macos)   ifconfig "$1" 2>/dev/null | awk '/inet /{print $2}' | head -1 | cut -d/ -f1 ;;
        windows) return 1 ;;
        *)       ip -4 addr show "$1" 2>/dev/null | awk '/inet /{print $2}' | head -1 | cut -d/ -f1 ;;
    esac
}

# Windows models VPNs as adapter categories, not interfaces, so there is nothing
# honest to probe here — the status board says so instead of guessing.
axiom_vpn_supported() { ! axiom_is_windows; }

# Interfaces that plausibly carry a VPN/host tunnel, WITH an assigned IPv4.
# On macOS every utun shows up in `ifconfig -l` even when idle, so an assigned
# address is the only honest signal.
axiom_vpn_ifaces() {
    if [[ -n "${AXIOM_VPN_IF:-}" ]]; then
        printf '%s\n' "$AXIOM_VPN_IF"
        return 0
    fi
    case "$(axiom_platform)" in
        macos)
            local n
            for n in $(ifconfig -l 2>/dev/null); do
                case "$n" in
                    utun*|tun*|ppp*|wg*)
                        [[ -n "$(iface_ipv4 "$n")" ]] && printf '%s\n' "$n"
                        ;;
                esac
            done
            ;;
        linux)
            for n in wg0 tun0 tun1 ppp0; do
                iface_exists "$n" && printf '%s\n' "$n"
            done
            ;;
        *)
            return 0
            ;;
    esac
    return 0
}

axiom_vpn_iface() {
    local n
    for n in $(axiom_vpn_ifaces); do
        printf '%s\n' "$n"
        return 0
    done
    return 1
}

# --- tor control port ------------------------------------------------------

# Talks the control protocol over socat (if present) or bash /dev/tcp.
#
# Commands are staged in a temp file rather than piped on stdin: an async list
# in a non-interactive shell has its stdin reassigned to /dev/null, so a piped
# heredoc would silently arrive empty and the control port would never see QUIT.
# All job-control noise is emitted by an inner `bash -c` with stderr dropped.
axiom_ctrl() {
    local port="${1:-}"
    [[ -n "$port" ]] || return 1

    local cookie="$AXIOM_TOR_DATA/control_auth_cookie" hex auth
    if [[ -r "$cookie" ]]; then
        hex=$(od -An -tx1 -v "$cookie" | tr -d ' \n')
        auth="AUTHENTICATE $hex"
    else
        auth='AUTHENTICATE ""'
    fi

    local cmdf outf tb
    cmdf=$(mktemp)
    outf=$(mktemp)
    printf '%s\nsignal NEWNYM\nQUIT\n' "$auth" > "$cmdf"
    tb=$(axiom_timeout_bin)

    if [[ -n "$tb" ]]; then
        if command -v socat >/dev/null 2>&1; then
            "$tb" 5 socat - "TCP:127.0.0.1:$port" < "$cmdf" > "$outf" 2>/dev/null || true
        else
            "$tb" 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port; cat >&3; cat <&3" \
                < "$cmdf" > "$outf" 2>/dev/null || true
        fi
    else
        bash -c '
            cmdf=$1; outf=$2; port=$3
            if command -v socat >/dev/null 2>&1; then
                socat - "TCP:127.0.0.1/$port" < "$cmdf" > "$outf" 2>/dev/null &
            else
                bash -c "exec 3<>/dev/tcp/127.0.0.1/$port; cat >&3; cat <&3" \
                    < "$cmdf" > "$outf" 2>/dev/null &
            fi
            p=$!
            ( sleep 5; kill -TERM "$p" 2>/dev/null; sleep 0.3; kill -KILL "$p" 2>/dev/null ) \
                >/dev/null 2>&1 &
            w=$!
            wait "$p" 2>/dev/null
            kill -TERM "$w" 2>/dev/null
            kill -KILL "$w" 2>/dev/null
            exit 0
        ' _ "$cmdf" "$outf" "$port" 2>/dev/null || true
    fi

    cat "$outf"
    rm -f "$cmdf" "$outf"
}

# --- proxy mode ------------------------------------------------------------

# kernel : proxychains4 present -> real LD_PRELOAD/DYLD hook of every child
# env    : no proxychains -> per-tool SOCKS env routing (honest, but partial)
axiom_proxy_mode() {
    if axiom_is_windows; then echo env; return; fi
    if command -v proxychains4 >/dev/null 2>&1; then echo kernel; else echo env; fi
}

axiom_proxy_env() {
    local socks="$1"
    ALL_PROXY="socks5h://127.0.0.1:$socks"    all_proxy="socks5h://127.0.0.1:$socks"
    http_proxy="socks5h://127.0.0.1:$socks"   https_proxy="socks5h://127.0.0.1:$socks"
    export ALL_PROXY all_proxy http_proxy https_proxy
}

axiom_env_mode_notice() {
    printf '  [!] no proxychains4 -> SOCKS ENV routing (per-tool, NOT a kernel tunnel)\n'
    printf '      curl/git/npm/wget route via Tor. ping, nc and other non-SOCKS tools BYPASS it.\n'
}