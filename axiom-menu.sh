#!/usr/bin/env bash
# axiom-menu.sh — home screen for the axiom multi-hop stack
# auto-engages on open, full stop on close
# macOS + Linux port.
set -uo pipefail

BASE="$HOME/.axiom"
# shellcheck source=axiom-lib.sh
source "$BASE/axiom-lib.sh"

DRV="$BASE/axiom-multihop.sh"
PIDF="$BASE/rotator.pid"
OWNERF="$BASE/rotator.owner"
IPF="$BASE/ip.cache"
ROTATE_INTERVAL="${AXIOM_ROTATE:-300}"
export AXIOM_IN_MENU=1

C_Y=$'\e[33m'; C_G=$'\e[32m'; C_R=$'\e[31m'
C_C=$'\e[36m'; C_M=$'\e[35m'; C_B=$'\e[1m'; C_D=$'\e[2m'; R=$'\e[0m'

rotator_pid() { [[ -f "$PIDF" ]] && cat "$PIDF" || echo ""; }

rotator_live() {
    local p; p=$(rotator_pid)
    [[ -n "$p" ]] && axiom_pid_alive "$p"
}

tor_state() {
    if [[ -n "$(tor_pid)" ]]; then printf '%sRUNNING%s (pid %s)' "$C_G" "$R" "$(tor_pid)"
    else printf '%sSTOPPED%s' "$C_R" "$R"; fi
}

tor_pid() {
    # our dedicated Tor only — identified by DataDirectory / SOCKS port, never a
    # foreign daemon the user started themselves
    local p
    p=$(axiom_tor_pid 2>/dev/null) && { echo "$p"; return 0; }
    # fall back to a live SOCKS port probe
    local socks; socks=$(axiom_socks_port)
    if curl -s --max-time 4 --socks5-hostname "127.0.0.1:$socks" \
        https://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; then
        echo "port:$socks"; return 0
    fi
    return 1
}

rotator_state() {
    if rotator_live; then printf '%sACTIVE%s (pid %s, rotate every %ss)' \
        "$C_G" "$R" "$(rotator_pid)" "$ROTATE_INTERVAL"
    else printf '%sOFF%s' "$C_R" "$R"; fi
}

vpn_up() { [[ -n "$(axiom_vpn_iface 2>/dev/null)" ]]; }

vpn_state_plain() {
    local iface ip
    iface=$(axiom_vpn_iface) || return 1
    ip=$(iface_ipv4 "$iface")
    printf 'UP (%s: %s)' "$iface" "${ip:-?}"
}

proxy_mode_label() {
    case "$(axiom_proxy_mode)" in
        kernel) printf '✅ kernel (proxychains4 hook)' ;;
        *)      printf '⚠️  per-tool (SOCKS env only)' ;;
    esac
}

chain_state() {
    if rotator_live && [[ -n "$(tor_pid)" ]]; then printf '%sON%s' "$C_G" "$R"
    else printf '%sOFF%s' "$C_R" "$R"; fi
}

refresh_ips() {
    local real="" exit_="" u socks
    socks=$(axiom_socks_port)
    for u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
        real=$(curl -s --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]')
        [[ "$real" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && break
        real=""
    done
    for u in https://api.ipify.org https://ifconfig.me/ip https://check.torproject.org/api/ip; do
        exit_=$(curl -s --max-time 20 --socks5-hostname "127.0.0.1:$socks" "$u" 2>/dev/null || true)
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
    if [[ -n "$own" && "$own" != "$$" ]] && axiom_pid_alive "$own" 2>/dev/null; then
        printf '  %s[i]%s chain stays ON — owned by another window (pid %s)\n' "$C_C" "$R" "$own"
        return 0
    fi
    if [[ -n "$p" ]]; then
        axiom_kill_tree "$p" TERM
        for i in 1 2 3 4 5 6 7 8; do
            axiom_pid_alive "$p" 2>/dev/null || break
            sleep 0.25
        done
        axiom_pid_alive "$p" 2>/dev/null && axiom_kill_tree "$p" KILL
        rm -f "$PIDF" "$OWNERF"
    fi
    "$DRV" stop >/dev/null 2>&1 || true
    rm -f "$AXIOM_PORTS_FILE"
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
        printf '  %-14s: ✅ ON (socks %s / ctrl %s)\n' "Chain" "$(axiom_socks_port)" "$(axiom_ctrl_port)"
    else
        printf '  %-14s: ❌ OFF\n' "Chain"
    fi
    if [[ -n "$(tor_pid)" ]]; then
        printf '  %-14s: ✅ RUNNING\n' "Tor daemon"
    else
        printf '  %-14s: ❌ STOPPED\n' "Tor daemon"
    fi
    if rotator_live; then
        printf '  %-14s: ✅ ACTIVE (pid %s, every %ss)\n' "Rotator" "$(rotator_pid)" "$ROTATE_INTERVAL"
    else
        printf '  %-14s: ❌ OFF\n' "Rotator"
    fi
    printf '  %-14s: %s\n' "Proxy mode" "$(proxy_mode_label)"
    if vpn_up; then
        printf '  %-14s: ✅ %s\n' "VPN" "$(vpn_state_plain)"
    elif axiom_vpn_supported; then
        printf '  %-14s: ❌ no iface (tor-only)\n' "VPN"
    else
        printf '  %-14s: – n/a on Windows (tor-only)\n' "VPN"
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
        if [[ "$(axiom_proxy_mode)" != kernel ]]; then
            printf '  %s[!]%s proxy mode = per-tool SOCKS env. Not every binary will route through Tor.\n' "$C_Y" "$R"
        fi
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
                   axiom_kill "$(rotator_pid)" TERM
                   rm -f "$PIDF"
                   engage
               fi ;;
            8|q|Q) disengage; exit 0 ;;
        esac
    done
}

main