# AXIOM CHAIN

**Multi-hop Tor proxy chain with a live home-screen menu — by CY3ER-CAT**

```
     _  __         ___   / \    __ _  ___ _ __   | | / _ \ _ __   __ _  __ _ ___
    | |/ /   ___  / _ \ / _ \  / _` |/ _ \ '_ \  | || | | | '_ \ / _` |/ _` / __|
    |   <   / _ \| | | |  __/ | (_| |  __/ | | | | || |_| | | | | (_| | (_| \__ \
    |_|\_\  \___/_| |_|\___|  \__,_|\___|_| |_| |_| \___/|_| |_|\__,_|\__, |___/
                                                                      |___/
```

One-click anonymization stack for your terminal: **Tor + proxychains** wired behind a
TUI home screen that connects on open, shows live status, and kills everything on close.

Open a terminal → you're already chained. Close it → nothing is left running.
No flags, no manual `tor &`, no forgetting to check whether your real IP is leaking.

---

## Why

Most proxychains setups are manual and silent: you start Tor by hand, hope the
circuit is fresh, never verify the exit, and forget what's running after you're done.
AXIOM CHAIN flips that:

- **The chain is the default.** The menu auto-engages the moment it opens and drops
  you straight into a chained shell — zero commands per session.
- **Nothing is assumed, everything is verified.** Before the chain is declared UP,
  a leak gate compares your real IP against the exit IP. If they match, the engage
  aborts instead of pretending you're hidden.
- **Lifecycle is airtight.** Quit the menu (or close the terminal) and every process
  we started — rotator, Tor instance, chained shell — dies with it. Nothing orphaned.

## Features

- **Auto-connect on open** — drop straight into a chained shell, zero setup per session
- **Live status board** — every line ticked ✅ or crossed ❌:

  | Line | Meaning |
  |---|---|
  | Chain | proxychains-attached shell / driver state |
  | Tor | Tor daemon alive? |
  | Rotator | circuit auto-rotation loop running? |
  | VPN | host-side VPN interface present (for VM users)? |
  | Real IP | your bare egress (pre-chain) |
  | Egress ISP | who the world actually sees — ASN + org of the exit |
  | Chain exit | current exit-node IP as seen through the chain |
  | Leak check | real IP ≠ exit IP? verdict recomputed live |

- **Leak gate** — engage aborts if your real IP ever matches the exit IP
- **Auto-rotation** — fresh Tor circuit every N seconds (default 300), each hop re-verified
- **Close = off** — quit the menu and every process dies clean (TERM, wait, KILL fallback)
- **Multi-window safe** — ownership lock: a second menu window can't kill the chain
  another window owns (each rotator records its owning PID)
- **Desktop launcher** — click-to-connect `.desktop` shortcut
- **Host-VPN aware** — the egress ISP line proves whether traffic rides your host VPN
  (useful when the VPN runs on the host and the tool runs in a VM)

## Requirements

- Linux (tested on Kali 2026.3, XFCE, aarch64; bash + zsh both wired)
- `tor`, `proxychains4`, `curl`:

```bash
sudo apt install tor proxychains4 curl
```

- Optional: any VPN on your host machine (VM traffic rides it automatically)

## Install

```bash
git clone https://github.com/CY3ER-CAT/AXIOM-CHAIN.git
cd AXIOM-CHAIN
./install.sh
```

What `install.sh` does (idempotent — safe to re-run after `git pull`):

1. Checks dependencies (`tor`, `proxychains4`, `curl`)
2. Copies the stack to `~/.axiom/` (scripts + `proxychains4.conf`)
3. Wires a guarded auto-boot block into **`~/.zshrc`** and **`~/.bashrc`**:
   interactive shells only, skipped when `AXIOM_NO_MENU` is set or a per-session
   marker (`/tmp/.axiom-booted-$XDG_SESSION_ID`) already fired — so the menu opens
   **once per login session**, not once per tab
4. Installs the `axiom` alias (both shells)
5. Drops the desktop shortcut:
   - `~/Desktop/AXIOM-Connect.desktop`
   - `~/.local/share/applications/axiom-connect.desktop`

The repo is the source of truth — re-run `./install.sh` whenever you `git pull`.

## Usage

| Action | How |
|---|---|
| Connect | Click **AXIOM-Connect** on desktop, or type `axiom`, or open a new terminal (auto-boot) |
| Work | You land in a chained shell — everything typed is routed through Tor |
| Back to menu | `exit` |
| Disconnect | Press `8` in the menu (or just close the terminal) |

Menu options:

```
1) Engage / re-check chain     — run the leak gate + rebuild status board
2) Disengage (stop chain)      — kill rotator + Tor, print OFF
3) Rotate circuit now          — force a fresh Tor circuit immediately
4) Refresh IPs + leak check    — re-query real IP, exit IP, egress ISP
5) Open chained shell          — new proxychains shell (no auto-retry)
6) Run a command through chain — one-shot: axiom-run <cmd>
7) Set rotation interval       — N seconds between auto-rotations
8) QUIT                        — stops everything owned by this window
```

**Environment variables:**

| Var | Default | Effect |
|---|---|---|
| `AXIOM_ROTATE` | `300` | circuit rotation interval (seconds) — `AXIOM_ROTATE=120 axiom` |
| `AXIOM_VPN_IF` | auto | force the VPN interface name to report on (e.g. `tun0`) |
| `AXIOM_NO_MENU` | unset | skip auto-boot entirely (plain shell) |
| `AXIOM_IN_MENU` | set internally | guard so the menu's own shell never re-triggers boot |

## How it works

```
  YOUR APP ──► proxychains (strict chain) ──► Tor guard ──► middle ──► exit ──► TARGET
                                                                        ▲
                                              host VPN (optional) ──────┘

  No single hop sees both ends. The leak gate runs before anything connects.
```

**Engage sequence:**

1. Spawn a dedicated Tor instance (own SocksPort/DataDirectory — never touches
   an already-running system Tor)
2. Wait for the circuit, then probe: real IP (direct) vs exit IP (through chain)
3. **Leak gate** — retry-backed (3 attempts, because transient `curl` timeouts must
   not abort the chain). Real IP == exit IP → engage FAILS, everything rolled back
4. Start the rotator watch loop: every N seconds → new circuit → re-verify → log
5. Status board renders; auto-shell launches chained

**Disengage sequence:** SIGTERM the rotator (and its children) → wait up to 2s →
SIGKILL fallback → remove pid/owner state files → shut down our Tor instance →
print `chain OFF`.

**File by file:**

| File | Role |
|---|---|
| `axiom-multihop.sh` | chain driver: boot Tor, leak gate, rotate, run commands, watch loop |
| `axiom-menu.sh` | home screen: banner, status board, auto-shell, lifecycle + ownership |
| `proxychains4.conf` | `strict_chain`, `proxy_dns`, `remote_dns_domain`, chain length, `[ProxyList]` |
| `install.sh` | deps check, copy to `~/.axiom`, rc wiring, desktop shortcut |
| `axiom-run` (via menu 6) | one-shot command through the chain |

## Config

- **Rotation interval:** menu option `7`, or `AXIOM_ROTATE=120 axiom`
- **VPN interface:** `AXIOM_VPN_IF=tun0 axiom`
- **Extra hops:** add entries to `[ProxyList]` in `~/.axiom/proxychains4.conf`
  (socks5 host port rows — each becomes another hop in the strict chain)
- **Logs:** `~/.axiom/stack.log` — rotation events, engage/disengage, leak verdicts

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `VPN ❌` on the board | No VPN interface on the **host**. Expected if you run none — chain still works |
| `Leak check ❌` | Real IP == exit IP (circuit or curl anomaly). Press `1` to re-gate, `3` to rotate |
| Engage takes ~10–30s | Leak gate retries on flaky networks — it's verifying, not hanging |
| Port 9050 already in use | Existing Tor detected — the stack uses its own SocksPort/DataDirectory instead |
| Second menu window quits, chain stays up | **By design** — ownership lock. The chain belongs to the window that engaged it |
| Menu didn't auto-open in a new tab | Per-session marker already fired; type `axiom` to open it on demand |
| Everything should run but nothing routes | `1` to engage, then check the board: Tor + Rotator must both be ✅ |

## Uninstall

```bash
rm -rf ~/.axiom
rm -f ~/Desktop/AXIOM-Connect.desktop ~/.local/share/applications/axiom-connect.desktop
# then delete the AXIOM auto-boot block + alias axiom line from ~/.zshrc and ~/.bashrc
```

## License

MIT — see [LICENSE](LICENSE).

---

**Authorized testing only.** Use this on systems you own or have written
permission to test. Hiding your IP is not a permission slip.

— **CY3ER-CAT**
