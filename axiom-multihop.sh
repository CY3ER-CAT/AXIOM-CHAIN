#!/usr/bin/env bash
# axiom-multihop.sh — VPN + multi-proxy chain, leak gate, auto-rotation
set -euo pipefail

BASE_DIR="$HOME/.axiom"
CHAIN_CONF="$BASE_DIR/proxychains4.conf"
TOR_SOCKS="127.0.0.1:9050"
TOR_CONTROL="127.0.0.1:9051"
VPN_IF="${AXIOM_VPN_IF:-wg0}"
ROTATE_INTERVAL="${AXIOM_ROTATE:-300}"

log() { printf '[\e[35mAXIOM\e[0m] %s\n' "$*"; }
die() { printf '[\e[31mAXIOM\e[0m] %s\n' "$*" >&2; exit 1; }

check_vpn() {
    if ip link show "$VPN_IF" >/dev/null 2>&1; then
        local vpn_ip
        vpn_ip=$(ip -4 addr show "$VPN_IF" | awk '/inet /{print $2}' | cut -d/ -f1)
        log "VPN tunnel alive: $vpn_ip"
    else
        log "No VPN interface ($VPN_IF) — chaining on Tor only, boss man."
    fi
}

start_tor() {
    if pgrep -x tor >/dev/null && curl -s --max-time 5 --socks5-hostname "$TOR_SOCKS" \
        https://check.torproject.org/api/ip >/dev/null 2>&1; then
        log "Tor already cookin' on $TOR_SOCKS."
        return
    fi
    log "Bootin' Tor daemon..."
    tor --RunAsDaemon 1 \
        --SocksPort "$TOR_SOCKS" \
        --ControlPort 9051 \
        --CookieAuthentication 0 \
        --HashedControlPassword ""
    local tries=0
    until curl -s --max-time 10 --socks5-hostname "$TOR_SOCKS" \
        https://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; do
        tries=$((tries + 1))
        [[ $tries -ge 30 ]] && die "Tor didn't bootstrap in time. The hell?"
        log "Waiting on Tor bootstrap ($tries)..."
        sleep 2
    done
    log "Tor circuit confirmed. Fuck yeah."
}

rotate_circuit() {
    log "Requesting fresh circuit..."
    if command -v socat >/dev/null 2>&1; then
        printf 'AUTHENTICATE ""\nsignal NEWNYM\nQUIT\n' \
            | timeout 5 socat - "TCP:$TOR_CONTROL" >/dev/null 2>&1 || true
    else
        printf 'AUTHENTICATE ""\nsignal NEWNYM\nQUIT\n' \
            | timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/9051; cat >&3; cat <&3" \
            >/dev/null 2>&1 || true
    fi
    sleep 2
}

leak_check() {
    log "Leak gate engaged..."
    local real_ip exit_ip tries
    for tries in 1 2 3; do
        real_ip=$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null || echo "?")
        exit_ip=$(curl -s --max-time 20 --socks5-hostname "$TOR_SOCKS" https://api.ipify.org 2>/dev/null || echo "?")
        [[ "$real_ip" != "?" && "$exit_ip" != "?" && -n "$real_ip" && -n "$exit_ip" ]] && break
        [[ $tries -lt 3 ]] && { log "Gate hiccup (attempt $tries) — retrying..."; sleep 3; }
    done
    [[ "$real_ip" == "unknown" || "$real_ip" == "?" || -z "$real_ip" ]] && die "Can't resolve real IP, couldn't verify. Abort."
    [[ "$exit_ip" == "?" || -z "$exit_ip" ]] && die "Exit IP unreachable through chain. Abort."
    [[ "$real_ip" == "$exit_ip" ]] && die "BUSTED — exit == real. Chain is leaking, abort."
    log "Real : $real_ip"
    log "Exit : $exit_ip"
    log "Chain verified. That's what the hell is going on."
}

proxy_run() {
    log "Chaining through VPN -> Tor -> hops: $*"
    proxychains4 -f "$CHAIN_CONF" -q "$@"
}

rotator_loop() {
    log "Auto-rotate every ${ROTATE_INTERVAL}s. Ctrl-C kills it."
    _sleep_pid=""
    _rotator_cleanup() {
        [[ -n "${_sleep_pid:-}" ]] && kill "$_sleep_pid" 2>/dev/null
        log "Rotator stopped."
        exit 0
    }
    trap _rotator_cleanup INT TERM HUP
    while true; do
        sleep "$ROTATE_INTERVAL" &
        _sleep_pid=$!
        wait "$_sleep_pid" 2>/dev/null || true
        _sleep_pid=""
        rotate_circuit
        leak_check || die "Leak detected mid-run, shutting down."
    done
}

usage() {
    cat <<EOF
usage: $0 <cmd>
  start   - verify VPN, boot Tor, run leak gate
  rotate  - force new circuit + re-verify
  watch   - background auto-rotation loop
  run ..  - execute command through full chain
  shell   - interactive shell inside the chain
EOF
    exit 1
}

case "${1:-}" in
    start)  check_vpn; start_tor; leak_check ;;
    rotate) rotate_circuit; leak_check ;;
    watch)  rotator_loop ;;
    run)    shift; check_vpn; start_tor; proxy_run "$@" ;;
    shell)  check_vpn; start_tor; proxy_run "${SHELL:-/bin/bash}" ;;
    *)      usage ;;
esac
