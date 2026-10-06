#!/usr/bin/env bash
# axiom-menu.sh — home screen for the axiom multi-hop stack
# auto-engages on open, full stop on close
set -uo pipefail

BASE="$HOME/.axiom"
DRV="$BASE/axiom-multihop.sh"
CHAIN="$BASE/proxychains4.conf"
PIDF="$BASE/rotator.pid"
OWNERF="$BASE/rotator.owner"
TORF="$BASE/tor.session"
IPF="$BASE/ip.cache"
ROTATE_INTERVAL="${AXIOM_ROTATE:-300}"
export AXIOM_IN_MENU=1

C_Y=$'\e[33m'; C_G=$'\e[32m'; C_R=$'\e[31m'
C_C=$'\e[36m'; C_M=$'\e[35m'; C_B=$'\e[1m'; C_D=$'\e[2m'; R=$'\e[0m'

tor_pid()      { pgrep -x tor 2>/dev/null | head -1; }
rotator_pid()  { [[ -f "$PIDF" ]] && cat "$PIDF" || echo ""; }

rotator_live() {
    local p; p=$(rotator_pid)
    [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null
}

tor_state() {
    local p; p=$(tor_pid)
    if [[ -n "$p" ]]; then printf '%sRUNNING%s (pid %s)' "$C_G" "$R" "$p"
    else printf '%sSTOPPED%s' "$C_R" "$R"; fi
}

rotator_state() {
    if rotator_live; then printf '%sACTIVE%s (pid %s, rotate every %ss)' \
        "$C_G" "$R" "$(rotator_pid)" "$ROTATE_INTERVAL"
    else printf '%sOFF%s' "$C_R" "$R"; fi
}

vpn_state() {
    local iface ip
    for iface in "${AXIOM_VPN_IF:-}" tun0 tun1 wg0 ppp0; do
        [[ -z "$iface" ]] && continue
        if ip link show "$iface" >/dev/null 2>&1; then
            ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
            printf '%sUP%s (%s: %s)' "$C_G" "$R" "$iface" "${ip:-?}"
            return
        fi
    done
    printf '%sDOWN%s (tor-only)' "$C_D" "$R"
}

chain_state() {
    if rotator_live && [[ -n "$(tor_pid)" ]]; then
        printf '%sON%s' "$C_G" "$R"
    else
        printf '%sOFF%s' "$C_R" "$R"
    fi
}

tor_state_plain()   { printf 'RUNNING (pid %s)' "$(tor_pid)"; }
rotator_state_plain(){ printf 'ACTIVE (pid %s, rotate every %ss)' "$(rotator_pid)" "$ROTATE_INTERVAL"; }

vpn_iface() {
    local iface
    for iface in "${AXIOM_VPN_IF:-}" tun0 tun1 wg0 ppp0; do
        [[ -z "$iface" ]] && continue
        ip link show "$iface" >/dev/null 2>&1 && { echo "$iface"; return; }
    done
    return 1
}

vpn_up() { vpn_iface >/dev/null 2>&1; }

vpn_state_plain() {
    local iface ip
    iface=$(vpn_iface) || return 1
    ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    printf 'UP (%s: %s)' "$iface" "${ip:-?}"
}

refresh_ips() {
    local real="" exit_="" u
    for u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
        real=$(curl -s --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]')
        [[ "$real" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && break
        real=""
    done
    for u in https://api.ipify.org https://ifconfig.me/ip https://check.torproject.org/api/ip; do
        exit_=$(curl -s --max-time 20 --socks5-hostname 127.0.0.1:9050 "$u" 2>/dev/null || true)
        if [[ "$u" == *check.torproject* ]]; then
            exit_=$(printf '%s' "$exit_" | sed -n 's/.*"IP"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        fi
        exit_=$(printf '%s' "$exit_" | tr -d '[:space:]')
        [[ "$exit_" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && break
        exit_=""
    done
    local verdict="UNKNOWN" color="$C_C"
    if [[ -n "$real" && -n "$exit_" ]]; then
        if [[ "$real" == "$exit_" ]]; then
            verdict="BUSTED"; color="$C_R"
        else
            verdict="CLEAN"; color="$C_G"
        fi
    fi
    local egress
    egress=$(curl -s --max-time 8 "http://ip-api.com/json/?fields=country,isp,as" 2>/dev/null \
        | sed -e 's/[{}"]//g' -e 's/^country://' -e 's/,isp:/ \/ /' -e 's/,as:/ \/ /' | tr -d '\n' || true)
    [[ -z "$egress" || "$egress" == *fail* ]] && egress="lookup failed"
    printf '%s|%s|%s|%s|%s\n' "$real" "$exit_" "$verdict" "$color" "$egress" > "$IPF"
}

ip_field() { [[ -f "$IPF" ]] && cut -d'|' -f"$1" "$IPF" || echo "?"; }

engage() {
    if rotator_live && [[ -n "$(tor_pid)" ]]; then
        # chain already live — make sure close=off can still find our tor
        [[ -f "$TORF" ]] || tor_pid > "$TORF" 2>/dev/null || true
        return 0
    fi
    printf '  %s[*]%s engaging chain — tor boot + leak gate...\n' "$C_Y" "$R"
    local attempt
    for attempt in 1 2 3; do
        if "$DRV" start; then
            break
        fi
        if [[ $attempt -eq 3 ]]; then
            printf '  %s[!]%s chain failed after 3 tries — check %s\n' "$C_R" "$R" "$BASE/stack.log"
            return 1
        fi
        printf '  %s[*]%s gate hiccup — retrying (%s/3)...\n' "$C_Y" "$R" "$((attempt + 1))"
        sleep 3
    done
    tor_pid > "$TORF" 2>/dev/null || true
    AXIOM_ROTATE="$ROTATE_INTERVAL" "$DRV" watch >> "$BASE/stack.log" 2>&1 &
    echo $! > "$PIDF"
    echo $$ > "$OWNERF"
    printf '  %s[+]%s chain engaged — rotator live\n' "$C_G" "$R"
    refresh_ips
    sleep 1
}

disengage() {
    local p i own
    p=$(rotator_pid)
    own=""
    [[ -f "$OWNERF" ]] && own=$(cat "$OWNERF" 2>/dev/null)
    if [[ -n "$own" && "$own" != "$$" ]] && kill -0 "$own" 2>/dev/null; then
        printf '  %s[i]%s chain stays ON — owned by another window (pid %s)\n' "$C_C" "$R" "$own"
        return 0
    fi
    if [[ -n "$p" ]]; then
        pkill -TERM -P "$p" 2>/dev/null || true
        kill -TERM "$p" 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8; do
            kill -0 "$p" 2>/dev/null || break
            sleep 0.25
        done
        if kill -0 "$p" 2>/dev/null; then
            pkill -KILL -P "$p" 2>/dev/null || true
            kill -KILL "$p" 2>/dev/null || true
        fi
        rm -f "$PIDF" "$OWNERF"
    fi
    if [[ -f "$TORF" ]]; then
        kill -TERM "$(cat "$TORF" 2>/dev/null)" 2>/dev/null || true
        rm -f "$TORF"
    fi
    printf '  %s[-]%s chain OFF — nothing routed, everything closed.\n' "$C_R" "$R"
}

draw() {
    clear 2>/dev/null || true
    printf '%s' "$C_M"
    cat <<'BANNER'
   ________  _______ __________        _________  ______
  / ____/\ \/ /__  // ____/ __ \      / ____/   |/_  __/
 / /      \  / /_ </ __/ / /_/ /_____/ /   / /| | / /
/ /___    / /___/ / /___/ _, _/_____/ /___/ ___ |/ /
\____/   /_//____/_____/_/ |_|      \____/_/  |_/_/
BANNER
    printf '%s' "$R"
    printf '  %s── SYSTEM STATUS ────────────────────────────────────────────%s\n' "$C_D" "$R"
    if [[ "$(rotator_pid)" != "" ]] && rotator_live && [[ -n "$(tor_pid)" ]]; then
        printf '  %-14s: ✅ ON\n' "Chain"
    else
        printf '  %-14s: ❌ OFF\n' "Chain"
    fi
    if [[ -n "$(tor_pid)" ]]; then
        printf '  %-14s: ✅ %s\n' "Tor daemon" "$(tor_state_plain)"
    else
        printf '  %-14s: ❌ STOPPED\n' "Tor daemon"
    fi
    if rotator_live; then
        printf '  %-14s: ✅ %s\n' "Rotator" "$(rotator_state_plain)"
    else
        printf '  %-14s: ❌ OFF\n' "Rotator"
    fi
    if vpn_up; then
        printf '  %-14s: ✅ %s\n' "VPN" "$(vpn_state_plain)"
    else
        printf '  %-14s: ❌ no iface in VM (host VPN? see Egress line)\n' "VPN"
    fi
    if [[ "$(ip_field 1)" != "?" && -n "$(ip_field 1)" ]]; then
        printf '  %-14s: ✅ %s\n' "Real IP" "$(ip_field 1)"
    else
        printf '  %-14s: ❌ unknown\n' "Real IP"
    fi
    if [[ "$(ip_field 5)" != "?" && -n "$(ip_field 5)" && "$(ip_field 5)" != "lookup failed" ]]; then
        printf '  %-14s: ✅ %s\n' "Egress ISP" "$(ip_field 5)"
    else
        printf '  %-14s: ❌ lookup failed\n' "Egress ISP"
    fi
    if [[ "$(ip_field 2)" != "?" && -n "$(ip_field 2)" ]]; then
        printf '  %-14s: ✅ %s\n' "Chain exit" "$(ip_field 2)"
    else
        printf '  %-14s: ❌ unknown\n' "Chain exit"
    fi
    case "$(ip_field 3)" in
        CLEAN)  printf '  %-14s: ✅ CLEAN\n' "Leak check" ;;
        BUSTED) printf '  %-14s: ❌ %sBUSTED%s\n' "Leak check" "$C_R" "$R" ;;
        *)      printf '  %-14s: ❓ UNKNOWN — press 4 to re-check\n' "Leak check" ;;
    esac
    printf '  %s── MENU ────────────────────────────────────────────────────%s\n' "$C_D" "$R"
    printf '  %s1)%s Engage / re-check chain\n'        "$C_C" "$R"
    printf '  %s2)%s Disengage (stop chain)\n'         "$C_C" "$R"
    printf '  %s3)%s Rotate circuit now\n'             "$C_C" "$R"
    printf '  %s4)%s Refresh IPs + leak check\n'       "$C_C" "$R"
    printf '  %s5)%s Open chained shell\n'             "$C_C" "$R"
    printf '  %s6)%s Run a command through chain\n'    "$C_C" "$R"
    printf '  %s7)%s Set rotation interval (now %ss)\n' "$C_C" "$R" "$ROTATE_INTERVAL"
    printf '  %s8)%s QUIT — stops everything\n'        "$C_C" "$R"
    printf '\n  %sclose the menu = chain off. "axiom" brings it back.%s\n' "$C_D" "$R"
}

main() {
    if engage; then
        draw
        printf '  %s▶ auto: chained shell starting — type %sexit%s to come back here%s\n' \
            "$C_G" "$C_B" "$C_G" "$R"
        "$DRV" shell || true
    else
        draw
        printf '  %s[!]%s chain NOT engaged — fix above, then press 1. menu stays open.\n' "$C_R" "$R"
        sleep 3
    fi
    while true; do
        draw
        read -rp $'  \e[35maxiom\e[0m ❯ ' choice || { disengage; exit 0; }
        case "$choice" in
            1) engage; read -rp "  press enter..." _ ;;
            2) disengage; read -rp "  press enter..." _ ;;
            3) "$DRV" rotate; read -rp "  press enter..." _ ;;
            4) printf '  %s[*]%s refreshing...\n' "$C_Y" "$R"; refresh_ips; read -rp "  press enter..." _ ;;
            5) "$DRV" shell; read -rp "  press enter..." _ ;;
            6) read -rp "  command: " cmdline
               [[ -n "$cmdline" ]] && "$DRV" run bash -c "$cmdline"
               read -rp "  press enter..." _ ;;
            7) read -rp "  rotation seconds: " ROTATE_INTERVAL
               ROTATE_INTERVAL="${ROTATE_INTERVAL:-300}"
               if rotator_live; then
                   kill -TERM "$(rotator_pid)" 2>/dev/null || true
                   rm -f "$PIDF"
                   engage
               fi ;;
            8|q|Q) disengage; exit 0 ;;
        esac
    done
}

main
