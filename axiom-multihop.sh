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

is_ipv4() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }

ip_direct() {
    local u ip
    for u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
        ip=$(curl -s --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]')
        is_ipv4 "$ip" && { echo "$ip"; return 0; }
    done
    return 1
}

ip_via_chain() {
    local u raw ip
    for u in https://api.ipify.org https://ifconfig.me/ip https://check.torproject.org/api/ip; do
        raw=$(curl -s --max-time 20 --socks5-hostname "$TOR_SOCKS" "$u" 2>/dev/null || true)
        if [[ "$u" == *check.torproject* ]]; then
            raw=$(printf '%s' "$raw" | sed -n 's/.*"IP"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        fi
        ip=$(printf '%s' "$raw" | tr -d '[:space:]')
        is_ipv4 "$ip" && { echo "$ip"; return 0; }
    done
    return 1
}

rotate_circuit() {
    log "Requesting fresh circuit..."
    local out=""
    if command -v socat >/dev/null 2>&1; then
        out=$(printf 'AUTHENTICATE ""\nsignal NEWNYM\nQUIT\n' \
            | timeout 5 socat - "TCP:$TOR_CONTROL" 2>/dev/null || true)
    else
        out=$( { printf 'AUTHENTICATE ""\nsignal NEWNYM\nQUIT\n'; sleep 0.5; } \
            | timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/9051; cat >&3; cat <&3" \
            2>/dev/null || true)
    fi
    if printf '%s' "$out" | grep -q "250"; then
        log "Circuit rotated — control port answered 250 OK."
        sleep 2
        return 0
    fi
    printf '[\e[31mAXIOM\e[0m] ROTATION FAILED — control port 9051 did not answer NEWNYM (dead or squatted). Check stack.log.\n' >&2
    return 1
}

# exit codes: 0 = verified clean, 1 = confirmed leak (real == exit), 2 = could not verify
leak_check() {
    log "Leak gate engaged..."
    local real_ip="" exit_ip="" tries
    for tries in 1 2 3; do
        real_ip=$(ip_direct 2>/dev/null || true)
        exit_ip=$(ip_via_chain 2>/dev/null || true)
        [[ -n "$real_ip" && -n "$exit_ip" ]] && break
        [[ $tries -lt 3 ]] && { log "Gate hiccup (attempt $tries) — retrying..."; sleep 3; }
    done
    if [[ -z "$real_ip" || -z "$exit_ip" ]]; then
        printf '[\e[31mAXIOM\e[0m] UNVERIFIED — could not confirm IPs this round (network flake, NOT a verdict).\n' >&2
        return 2
    fi
    log "Real : $real_ip"
    log "Exit : $exit_ip"
    if [[ "$real_ip" == "$exit_ip" ]]; then
        printf '[\e[31mAXIOM\e[0m] BUSTED — exit == real. Chain is leaking, abort.\n' >&2
        return 1
    fi
    log "Chain verified. That's what the hell is going on."
    return 0
}

proxy_run() {
    log "Running through the chain: $*"
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
    local rc
    while true; do
        sleep "$ROTATE_INTERVAL" &
        _sleep_pid=$!
        wait "$_sleep_pid" 2>/dev/null || true
        _sleep_pid=""
        rotate_circuit || log "Rotation signal failed — will retry next cycle."
        rc=0
        leak_check || rc=$?
        if [[ $rc -eq 1 ]]; then
            die "Leak detected mid-run (real == exit), shutting down."
        elif [[ $rc -eq 2 ]]; then
            log "Couldn't verify this round — staying up, re-checking next cycle."
        fi
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
    rotate) rotate_circuit || log "Continuing — verifying circuit anyway..."; leak_check ;;
    watch)  rotator_loop ;;
    run)    shift; check_vpn; start_tor; proxy_run "$@" ;;
    shell)  check_vpn; start_tor; proxy_run "${SHELL:-/bin/bash}" ;;
    *)      usage ;;
esac
