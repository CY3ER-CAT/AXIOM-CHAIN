#!/usr/bin/env bash
# axiom-multihop.sh — VPN + multi-proxy chain, leak gate, auto-rotation
# macOS + Linux port.
set -euo pipefail

BASE_DIR="$HOME/.axiom"
# shellcheck source=axiom-lib.sh
source "$BASE_DIR/axiom-lib.sh"

CHAIN_CONF="$BASE_DIR/proxychains4.conf"
ROTATE_INTERVAL="${AXIOM_ROTATE:-300}"

die() { axiom_err "$*"; exit 1; }

socks_port() { axiom_socks_port; }
ctrl_port()  { axiom_ctrl_port; }

check_vpn() {
    if axiom_is_windows; then
        axiom_log "Windows: VPN reported via adapter category, not an interface — chaining on Tor only."
        return 0
    fi
    local i ip found=0
    while read -r i; do
        [[ -z "$i" ]] && continue
        ip=$(iface_ipv4 "$i")
        axiom_log "VPN tunnel alive: $i ${ip:-?}"
        found=1
    done < <(axiom_vpn_ifaces)
    [[ $found -eq 0 ]] && axiom_log "No VPN interface detected — chaining on Tor only, boss man."
    return 0
}

start_tor() {
    local socks ctrl
    socks=$(socks_port)
    ctrl=$(ctrl_port)

    # already ours and answering? then nothing to do
    if curl -s --max-time 6 --socks5-hostname "127.0.0.1:$socks" \
        https://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; then
        axiom_log "Tor already cookin' on 127.0.0.1:$socks."
        return
    fi

    # pick a free port pair so we NEVER collide with a system Tor (brew service)
    if ! port_free "$socks"; then
        axiom_log "Port $socks busy — moving our dedicated Tor to a free pair."
        socks=$((socks + 100)); ctrl=$((ctrl + 100))
        while ! port_free "$socks" || ! port_free "$ctrl"; do
            socks=$((socks + 2)); ctrl=$((ctrl + 2))
        done
        printf '%s %s\n' "$socks" "$ctrl" > "$AXIOM_PORTS_FILE"
    else
        printf '%s %s\n' "$socks" "$ctrl" > "$AXIOM_PORTS_FILE"
    fi

    axiom_log "Bootin' dedicated Tor daemon (data: $AXIOM_TOR_DATA)..."
    mkdir -p "$AXIOM_TOR_DATA"
    local tor_args=(
        --DataDirectory "$AXIOM_TOR_DATA"
        --ClientOnly 1
        --SocksPort "$socks"
        --ControlPort "$ctrl"
        --CookieAuthentication 1
        --AvoidDiskWrites 1
    )
    if axiom_is_windows; then
        # tor.exe has no --RunAsDaemon; background it from the shell instead.
        tor "${tor_args[@]}" --Log 'notice stdout' >> "$AXIOM_BASE/tor.out" 2>&1 &
    else
        tor "${tor_args[@]}" --RunAsDaemon 1 --Log 'notice stdout'
    fi

    local tries=0
    until curl -s --max-time 10 --socks5-hostname "127.0.0.1:$socks" \
        https://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; do
        tries=$((tries + 1))
        [[ $tries -ge 30 ]] && die "Tor didn't bootstrap in time. The hell?"
        axiom_log "Waiting on Tor bootstrap ($tries)..."
        sleep 2
    done
    axiom_log "Tor circuit confirmed. Fuck yeah."
}

stop_tor() {
    local socks p
    socks=$(socks_port)
    # only ever the Tor we started, identified by DataDirectory (or SOCKS port)
    for p in $(axiom_pids tor); do
        if axiom_pid_is_tor "$p"; then
            axiom_kill_tree "$p" KILL
        fi
    done
    rm -f "$AXIOM_PORTS_FILE"
    axiom_log "Dedicated Tor on $socks stopped."
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
    local socks u raw ip
    socks=$(socks_port)
    for u in https://api.ipify.org https://ifconfig.me/ip https://check.torproject.org/api/ip; do
        raw=$(curl -s --max-time 20 --socks5-hostname "127.0.0.1:$socks" "$u" 2>/dev/null || true)
        if [[ "$u" == *check.torproject* ]]; then
            raw=$(printf '%s' "$raw" | sed -n 's/.*"IP"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        fi
        ip=$(printf '%s' "$raw" | tr -d '[:space:]')
        is_ipv4 "$ip" && { echo "$ip"; return 0; }
    done
    return 1
}

rotate_circuit() {
    axiom_log "Requesting fresh circuit..."
    local out
    out=$(axiom_ctrl "$(ctrl_port)" || true)
    if printf '%s' "$out" | grep -q '250' && ! printf '%s' "$out" | grep -q '515'; then
        axiom_log "Circuit rotated — control port answered 250 OK (cookie auth)."
        sleep 2
        return 0
    fi
    axiom_err "ROTATION FAILED — control port did not answer NEWNYM. Check stack.log."
    printf '%s\n' "$out" >> "$AXIOM_BASE/stack.log" 2>/dev/null || true
    return 1
}

# exit codes: 0 = verified clean, 1 = confirmed leak, 2 = could not verify
leak_check() {
    axiom_log "Leak gate engaged..."
    local real_ip="" exit_ip="" tries
    for tries in 1 2 3; do
        real_ip=$(ip_direct 2>/dev/null || true)
        exit_ip=$(ip_via_chain 2>/dev/null || true)
        [[ -n "$real_ip" && -n "$exit_ip" ]] && break
        [[ $tries -lt 3 ]] && { axiom_log "Gate hiccup (attempt $tries) — retrying..."; sleep 3; }
    done
    if [[ -z "$real_ip" || -z "$exit_ip" ]]; then
        axiom_err "UNVERIFIED — could not confirm IPs this round (network flake, NOT a verdict)."
        return 2
    fi
    axiom_log "Real : $real_ip"
    axiom_log "Exit : $exit_ip"
    if [[ "$real_ip" == "$exit_ip" ]]; then
        axiom_err "BUSTED — exit == real. Chain is leaking, abort."
        return 1
    fi
    axiom_log "Chain verified. That's what the hell is going on."
    return 0
}

proxy_run() {
    local socks mode
    socks=$(socks_port)
    mode=$(axiom_proxy_mode)
    axiom_log "Running through the chain [$mode]: $*"
    if [[ "$mode" == kernel ]]; then
        proxychains4 -f "$CHAIN_CONF" -q "$@"
    else
        axiom_env_mode_notice
        axiom_proxy_env "$socks"
        "$@"
    fi
}

rotator_loop() {
    axiom_log "Auto-rotate every ${ROTATE_INTERVAL}s. Ctrl-C kills it."
    _sleep_pid=""
    _rotator_cleanup() {
        [[ -n "${_sleep_pid:-}" ]] && kill "$_sleep_pid" 2>/dev/null
        axiom_log "Rotator stopped."
        exit 0
    }
    trap _rotator_cleanup INT TERM HUP
    local rc
    while true; do
        sleep "$ROTATE_INTERVAL" &
        _sleep_pid=$!
        wait "$_sleep_pid" 2>/dev/null || true
        _sleep_pid=""
        rotate_circuit || axiom_log "Rotation signal failed — will retry next cycle."
        rc=0
        leak_check || rc=$?
        if [[ $rc -eq 1 ]]; then
            die "Leak detected mid-run (real == exit), shutting down."
        elif [[ $rc -eq 2 ]]; then
            axiom_log "Couldn't verify this round — staying up, re-checking next cycle."
        fi
    done
}

usage() {
    cat <<EOF
usage: $0 <cmd>
  start   - verify VPN, boot Tor, run leak gate
  stop    - stop our dedicated Tor instance
  rotate  - force new circuit + re-verify
  watch   - background auto-rotation loop
  run ..  - execute command through the chain
  shell   - interactive shell inside the chain
EOF
    exit 1
}

case "${1:-}" in
    start)  check_vpn; start_tor; leak_check ;;
    stop)   stop_tor ;;
    rotate) rotate_circuit || axiom_log "Continuing — verifying circuit anyway..."; leak_check ;;
    watch)  rotator_loop ;;
    run)    shift; check_vpn; start_tor; proxy_run "$@" ;;
    shell)  check_vpn; start_tor; proxy_run "${SHELL:-/bin/bash}" ;;
    *)      usage ;;
esac