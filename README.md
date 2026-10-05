# AXIOM CHAIN

**Multi-hop proxy chain with a live home-screen menu — by CY3ER-CAT**

```
     _  __         ___   / \    __ _  ___ _ __   | | / _ \ _ __   __ _  __ _ ___
    | |/ /   ___  / _ \ / _ \  / _` |/ _ \ '_ \  | || | | | '_ \ / _` |/ _` / __|
    |   <   / _ \| | | |  __/ | (_| |  __/ | | | | || |_| | | | | (_| | (_| \__ \
    |_|\_\  \___/_| |_|\___|  \__,_|\___|_| |_| |_| \___/|_| |_|\__,_|\__, |___/
                                                                      |___/
```

One-click anonymization stack for your terminal: **Tor + proxychains** wired behind a
TUI home screen that connects on open, shows live status, and kills everything on close.

## Features

- **Auto-connect on open** — drop straight into a chained shell, zero setup per session
- **Live status board** — chain / tor / rotator / VPN / real IP / egress ISP / leak verdict, every line ticked or crossed
- **Leak gate** — aborts if your real IP ever matches the exit IP
- **Auto-rotation** — fresh Tor circuit every N seconds, re-verified each hop
- **Close = off** — quit the menu and every process dies clean
- **Desktop launcher** — click-to-connect `.desktop` shortcut
- **Host-VPN aware** — egress ISP line verifies VPNs running outside the VM

## Requirements

- Linux (tested on Kali 2026.3, XFCE)
- `tor`, `proxychains4`, `curl` — `sudo apt install tor proxychains4 curl`
- Optional: any VPN on your host machine (VM traffic rides it automatically)

## Install

```bash
git clone https://github.com/CY3ER-CAT/axiom-chain.git
cd axiom-chain
./install.sh
```

`install.sh` copies the scripts to `~/.axiom`, wires auto-boot into your shell rc,
and drops the desktop shortcut.

## Usage

| Action | How |
|---|---|
| Connect | Click **AXIOM-Connect** on desktop, or type `axiom` |
| Work | You land in a chained shell — everything typed is hidden |
| Back to menu | `exit` |
| Disconnect | Press `8` in the menu (or close it) |

Menu options:

```
1) Engage / re-check chain
2) Disengage (stop chain)
3) Rotate circuit now
4) Refresh IPs + leak check
5) Open chained shell
6) Run a command through chain
7) Set rotation interval
8) QUIT — stops everything
```

## How it works

```
  YOUR APP ──► proxychains (strict chain) ──► Tor guard ──► middle ──► exit ──► TARGET
                                                                        ▲
                                              host VPN (optional) ──────┘

  No single hop sees both ends. The leak gate runs before anything connects.
```

- `axiom-multihop.sh` — chain driver: boot, leak gate, rotate, run, watch loop
- `axiom-menu.sh` — home screen: status board, auto-shell, lifecycle control
- `proxychains4.conf` — strict chain config, DNS forced through tunnel

## Config

- Rotation interval: menu option `7`, or `AXIOM_ROTATE=120 axiom`
- VPN interface: `AXIOM_VPN_IF=tun0 axiom`
- Extra hops: add entries to `[ProxyList]` in `~/.axiom/proxychains4.conf`

## License

MIT — see [LICENSE](LICENSE).

---

**Authorized testing only.** Use this on systems you own or have written
permission to test. Hiding your IP is not a permission slip.

— **CY3ER-CAT**
