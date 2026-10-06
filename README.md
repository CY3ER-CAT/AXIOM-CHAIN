# AXIOM CHAIN

> ### ⚠️ DISCLAIMER — PLEASE READ
>
> **This project is provided for EDUCATIONAL, RESEARCH, and INFORMATIONAL PURPOSES ONLY.**
>
> It exists to demonstrate and teach how Tor, SOCKS proxying, circuit rotation, IP-leak
> detection, and Bash scripting work — nothing more. It is not a hacking tool, not an
> anonymity product, and not a recommendation to conceal yourself online.
>
> By downloading, running, or using this software you agree that:
>
> - **You are solely responsible for how you use it.** Any illegal, harmful, abusive,
>   deceptive, or privacy-invasive use is entirely your own doing.
> - **The authors and this GitHub repository accept NO liability whatsoever** for any
>   damage, loss, data breach, account suspension, legal action, fine, prosecution,
>   censorship, or any other consequence — direct or indirect — arising from your use of,
>   or inability to use, this software. This includes consequences caused by misuse,
>   misconfiguration, or violation of any law or third-party terms of service.
> - **This software is provided "AS IS", WITHOUT WARRANTY OF ANY KIND**, express or
>   implied. Do not rely on it for your safety, anonymity, or privacy.
> - **You are responsible for obeying the law.** Anonymity and proxy tools are restricted or
>   illegal in some jurisdictions and may breach your ISP, employer, school, or provider
>   terms of service. Check your local regulations before running anything.
> - **A new circuit is not a new identity.** Nothing here defeats account-level tracking,
>   browser fingerprinting, or behavioural correlation. Do not treat it as a guarantee.
>
> If you are unsure whether a given use is lawful, do not perform it.

```
     _  __         ___   / \    __ _  ___ _ __   | | / _ \ _ __   __ _  __ _ ___
    | |/ /   ___  / _ \ / _ \  / _` |/ _ \ '_ \  | || | | | '_ \  / _` | / _` / __|
    |   <   / _ \| | | |  __/ | (_| |  __/ | | | | || |_| | | | | (_| | (_| \__ \
    |_|\_\  \___/_| |_|\___|  \__,_|\___|_| |_| |_| \___/|_| |_|\__,_|\__, |___/
                                                                        |___/
```

**Multi-hop Tor proxy chain with a live home-screen menu — built for Kali Linux.**

One-click anonymization stack for your terminal: **Tor + proxychains** behind a TUI home
screen that connects on open, shows live status, and kills everything on close.

Open a terminal → you're already chained. Close it → nothing is left running.

---

## 🎯 Kali Linux — the primary target

**Kali is the reference platform for this project.** It is where the code was written, where
`proxychains4` is available in the default repositories, and where you get the **full
`kernel` tunnel** — every TCP connection from every process in the shell is hooked through
Tor, with no exceptions and no per-tool caveats.

One command gets you there:

```bash
sudo apt update && sudo apt install -y tor proxychains4 curl
```

Then:

```bash
git clone https://github.com/CY3ER-CAT/AXIOM-CHAIN-UNIVERSAL.git
cd AXIOM-CHAIN-UNIVERSAL
./install.sh
```

Open a terminal. You're chained.

**Verified on:** Kali 2026.3 · XFCE · aarch64 · `bash` **and** `zsh` both wired.
`proxychains4` is confirmed working in the status board as `Proxy mode: ✅ kernel`.

### Why Kali gets the best experience

| | Kali (with `proxychains4`) | macOS / Windows |
|---|---|---|
| Proxy mode | `✅ kernel` — **full tunnel** | `⚠️ env` — per-tool only |
| `curl`, `git`, `npm` | ✅ via Tor | ✅ via Tor |
| `ping`, `nc`, other TCP tools | ✅ via Tor | ❌ **bypass the chain** |
| Verdict | genuine full-tunnel anonymity | IP-layer hardening only |

Kali is the only platform where every tool in the shell is inside the chain. If you need a
real full tunnel, this is the platform to run it on.

### Kali notes

- **`sudo` is not needed to run it.** `install.sh` writes only to `~/.axiom`, your shell rc,
  and your Desktop. Tor is bound to loopback only.
- **XFCE / GNOME / MATE** all work — the launcher is a standard `.desktop` entry, and the
  menu itself is plain terminal output.
- **Kali in a VM:** if your VPN runs on the *host*, VM traffic rides it automatically. The
  `VPN` line on the status board reports whether a tunnel interface (`wg0`, `tun0`, `tun1`,
  `ppp0`) is up, and `Egress ISP` proves which carrier the world actually sees.
- **Multiple shells:** auto-boot is wired into both `~/.zshrc` and `~/.bashrc`. Kali
  defaults to `zsh`; both are covered.
- **Don't fight the marker:** `XDG_SESSION_ID` is set on a normal Kali session, so the menu
  auto-opens **once per login**, not once per tab. Type `axiom` to bring it back on demand.

---

## Platform support

| Platform | Status | Proxy mode |
|---|---|---|
| **Kali Linux** | ✅ **Primary target** — reference platform | `kernel` (full tunnel) |
| **Debian / Ubuntu** | ✅ Supported — same `apt` path | `kernel` with `proxychains4` |
| **Any Linux / WSL** | ✅ Supported | `kernel` with `proxychains4` |
| macOS | ✅ Supported — tested exhaustively | `env` (SIP blocks kernel mode) |
| Windows (Git Bash) | ⚠️ Experimental — untested, no CI | `env` always |

> **Honesty note:** the Kali/Linux path is the original upstream implementation and is the
> platform this project is designed around. The macOS port was verified end-to-end on real
> hardware. The Windows/Git Bash path was written but **could not be tested** — there is no
> Windows machine or CI runner in this project's history. On Windows, prefer **WSL**: it is
> real Linux, so the Kali code path runs unmodified.

---

## Why

Most Tor/proxy setups on Kali are manual and silent: you start Tor by hand, hope the circuit
is fresh, never verify the exit, and forget what's running after you're done. AXIOM CHAIN
flips that:

- **The chain is the default.** The menu auto-engages the moment it opens and drops you
  straight into a chained shell — zero commands per session.
- **Nothing is assumed, everything is verified.** Before the chain is declared UP, a leak
  gate compares your real IP against the exit IP. If they match, the engage aborts instead
  of pretending you're hidden.
- **Lifecycle is airtight.** Quit the menu (or close the terminal) and every process we
  started — rotator, Tor instance, chained shell — dies with it. Nothing orphaned.
- **It never touches your other Tor.** A dedicated `DataDirectory` and port pair mean a
  `systemctl` Tor or a Tor Browser instance keeps running untouched.

## Features

- **Auto-connect on open** — drop straight into a chained shell, zero setup per session
- **Live status board** — every line ticked ✅ or crossed ❌:

  | Line | Meaning |
  |---|---|
  | Chain | proxychains-attached shell / driver state (with live SOCKS + control ports) |
  | Tor | our dedicated Tor daemon alive? |
  | Rotator | circuit auto-rotation loop running? |
  | **Proxy mode** | **`kernel` (real full tunnel) or `env` (per-tool only)** |
  | VPN | host-side VPN interface present (for VM users)? |
  | Real IP | your bare egress (pre-chain) |
  | Egress ISP | who the world actually sees — country / org / ASN of the exit |
  | Chain exit | current exit-node IP as seen through the chain |
  | Leak check | real IP ≠ exit IP? verdict recomputed live |

- **Leak gate** — engage aborts if your real IP ever matches the exit IP (verdicts:
  `CLEAN` / `BUSTED` / `UNKNOWN` — a network flake reports UNKNOWN, never a fake CLEAN)
- **Auto-rotation** — fresh Tor circuit every N seconds (default 300); every rotation is
  **verified** (control port must answer `250`) and the new exit re-checked. Failures are
  loud; a flaky network warns instead of killing the rotator
- **Close = off** — quit the menu and every process dies clean (TERM, wait, KILL fallback)
- **Multi-window safe** — ownership lock: a second menu window can't kill the chain another
  window owns (each rotator records its owning PID)
- **Desktop launcher** — click-to-connect on all platforms

---

## Requirements

### Kali Linux / Debian / Ubuntu

All three ship in the default repositories:

```bash
sudo apt update && sudo apt install -y tor proxychains4 curl
```

- **`tor`** — the anonymisation network daemon
- **`proxychains4`** — the `LD_PRELOAD` hook that makes the `kernel` full tunnel possible.
  Without it the stack degrades to `env` mode.
- **`curl`** — used for every IP lookup and the leak gate
- **`bash` 3.2+** — Kali's default is `zsh`; both are supported and wired

### macOS

```bash
brew install tor curl
```

No `proxychains4` — see [Proxy modes](#proxy-modes--read-this-before-you-trust-it).

### Windows (WSL — recommended)

```powershell
wsl --install -d Kali
```

Then use the Kali instructions above inside WSL. **This is the recommended Windows setup** —
you get the full `kernel` tunnel, because WSL is real Linux.

### Windows (Git Bash — experimental)

Install the [Tor Expert Bundle](https://www.torproject.org/download/tor-package/) and put
`tor.exe` and `curl.exe` on your `PATH`. There is no `proxychains4` for Windows, so you will
be in `env` mode.

---

## Install

### Kali Linux

```bash
git clone https://github.com/CY3ER-CAT/AXIOM-CHAIN-UNIVERSAL.git
cd AXIOM-CHAIN-UNIVERSAL
./install.sh
```

What `install.sh` does — idempotent, so it's safe to re-run after every `git pull`:

1. **Checks dependencies** (`tor`, `curl`) and reports which proxy mode you'll get
2. **Syntax-checks every script with `bash -n` before touching `$HOME`** — a typo can't
   break your shell
3. **Copies the stack to `~/.axiom/`** (scripts + `proxychains4.conf`)
4. **Wires a guarded auto-boot block into `~/.zshrc` and `~/.bashrc`** — interactive shells
   only, skipped when `AXIOM_NO_MENU` is set or a per-session marker already fired
5. **Installs the `axiom` alias** in both shells
6. **Drops the desktop launcher** for your platform:

   | Platform | Launcher |
   |---|---|
   | **Kali / Linux** | `~/Desktop/AXIOM-Connect.desktop` + `~/.local/share/applications/axiom-connect.desktop` |
   | macOS | `~/Desktop/AXIOM-Connect.command` |
   | Windows | `%USERPROFILE%\Desktop\AXIOM-Connect.cmd` |

On Kali the launcher is a proper `.desktop` entry, so it shows up in the XFCE/GNOME/MATE
application menu and can be pinned to a panel. Mark it trusted if your desktop asks
(right-click → *Allow Launching*).

The repo is the source of truth — re-run `./install.sh` whenever you `git pull`.

## Usage

| Action | How |
|---|---|
| Connect | Click **AXIOM-Connect**, or type `axiom`, or open a new terminal (auto-boot) |
| Work | You land in a chained shell — everything typed is routed through Tor |
| Back to menu | `exit` |
| Disconnect | Press `8` in the menu (or just close the terminal) |
| Force-stop the daemon | `~/.axiom/axiom-multihop.sh stop` |

Menu options:

```
1) Engage / re-check chain     — run the leak gate + rebuild status board
2) Disengage (stop chain)      — kill rotator + Tor, print OFF
3) Rotate circuit now          — force a fresh Tor circuit immediately
4) Refresh IPs + leak check    — re-query real IP, exit IP, egress ISP
5) Open chained shell          — new proxied shell
6) Run a command through chain — one-shot: axiom-multihop.sh run <cmd>
7) Set rotation interval       — N seconds between auto-rotations
8) QUIT                        — stops everything owned by this window
```

### One-shot commands from a normal shell

You don't have to enter the menu to route a single command:

```bash
~/.axiom/axiom-multihop.sh run nmap -sT scanme.nmap.org
~/.axiom/axiom-multihop.sh run curl https://api.ipify.org
~/.axiom/axiom-multihop.sh shell          # interactive proxied shell
```

**Environment variables:**

| Var | Default | Effect |
|---|---|---|
| `AXIOM_ROTATE` | `300` | circuit rotation interval (seconds) — `AXIOM_ROTATE=120 axiom` |
| `AXIOM_VPN_IF` | auto | force the VPN interface name to report on (e.g. `tun0`) |
| `AXIOM_NO_MENU` | unset | skip auto-boot entirely (plain shell) |
| `AXIOM_SESSION_KEY` | `$XDG_SESSION_ID` or `$$` | makes the auto-boot marker stable per session |
| `AXIOM_IN_MENU` | set internally | guard so the menu's own shell never re-triggers boot |
| `AXIOM_BASE` | `~/.axiom` | relocate state — run two isolated instances |

---

## Proxy modes — read this before you trust it

The stack reports its mode on the **`Proxy mode`** status line. The two modes are **not**
equivalent, and the board will never lie to you about which one you have.

### `✅ kernel` — full tunnel *(Kali, with `proxychains4`)*

`proxychains4` uses `LD_PRELOAD` to interpose on `connect()` in every child process. The
result is a genuine full tunnel: `curl`, `git`, `npm`, `python`, `ssh`, and any other tool
you run are all inside the chain without knowing it.

**This is the mode Kali gives you, and it is the reason to run it there.**

### `⚠️ env` — per-tool routing *(macOS, Windows, or Kali without `proxychains4`)*

The stack exports `ALL_PROXY` / `all_proxy` / `http_proxy` / `https_proxy` as
`socks5h://127.0.0.1:9050` and execs your command.

| Routed through Tor | **Bypasses the chain** |
|---|---|
| `curl`, `wget`, `git`, `npm`, `pip`, most HTTP clients | `ping` (ICMP), `nc`, `ssh` (needs `ProxyCommand`), anything SOCKS-unaware |

**The leak gate stays accurate in `env` mode** — it probes with `curl --socks5-hostname`
directly rather than trusting the env vars. So a green `Leak check` means the *chain* is
sound; it does **not** mean every binary on your machine is inside it.

**Fix it on Kali:** `sudo apt install proxychains4`, then press `1` at the menu to re-engage.
The board will read `Proxy mode: ✅ kernel`.

---

## How it works

```
  YOUR APP ──► proxychains (strict chain) ──► Tor guard ──► middle ──► exit ──► TARGET
                                                                        ▲
                                              host VPN (optional) ──────┘

  No single hop sees both ends. The leak gate runs before anything connects.
```

**Engage sequence:**

1. Detect any free SOCKS/control port pair (so a `systemctl`-managed Tor is never disturbed)
   and spawn a **dedicated Tor instance** with its own `DataDirectory`
2. Wait for the circuit, then probe: real IP (direct) vs exit IP (through chain)
3. **Leak gate** — retry-backed with fallback IP services (3 attempts, because transient
   `curl` timeouts must not abort the chain). Three outcomes: `CLEAN` (verified) /
   `BUSTED` (real == exit → engage FAILS, rolled back) / `UNKNOWN` (couldn't verify →
   engage FAILS, never fake-green)
4. Start the rotator watch loop: every N seconds → NEWNYM (control port must answer `250`,
   else it's logged loudly) → leak gate re-run. A confirmed leak kills the rotator; a
   network flake only warns and waits for the next cycle
5. Status board renders; auto-shell launches chained

**Disengage sequence:** SIGTERM the rotator (and its children) → wait up to 2s → SIGKILL
fallback → remove pid/owner state files → shut down our Tor instance → print `chain OFF`.

**File by file:**

| File | Role |
|---|---|
| `axiom-lib.sh` | platform detection + all OS-specific helpers (process, ports, ifaces, control port) |
| `axiom-multihop.sh` | chain driver: boot Tor, leak gate, rotate, run commands, watch loop |
| `axiom-menu.sh` | home screen: banner, status board, auto-shell, lifecycle + ownership |
| `proxychains4.conf` | `strict_chain`, `proxy_dns`, `remote_dns_subnet`, `[ProxyList]` |
| `install.sh` | deps check, syntax check, copy to `~/.axiom`, rc wiring, desktop launcher |

On Kali the `linux` branch of `axiom-lib.sh` is all that's ever exercised — every other
platform's code is inert. All OS-specific behaviour is confined to that one file, so adding
a platform later doesn't touch the other three scripts.

## Kali-specific security notes

- **Control port is cookie-authenticated.** Earlier versions ran
  `--CookieAuthentication 0 --HashedControlPassword ""`, which accepts `AUTHENTICATE ""`
  from *any* local process — letting anything on the box force NEWNYM or read circuit
  state. Now it uses a 32-byte cookie in the private `DataDirectory`.
  Verify it yourself on Kali:

  ```bash
  printf 'GETINFO version\r\nQUIT\r\n' | nc 127.0.0.1 9051
  # -> 514 Authentication required.
  ```

- **Dedicated instance only.** Teardown matches our own Tor by `DataDirectory` — a Tor you
  started yourself (Tor Browser, `systemctl start tor`) is never killed.
- **Loopback only.** SOCKS and control listeners bind `127.0.0.1`.
- **No `sudo` at runtime.** Everything lives in `~/.axiom` owned by your user.
- **⚠️ On a shared multi-user Kali box:** `~/.axiom/tor-data/control_auth_cookie` is
  readable by your account. That's fine on a single-user system. If others have shell
  access to your user, don't rely on the control port being a trust boundary.

## What this does NOT do

Be honest with yourself before you trust any anonymizer — including this one:

- **New circuit ≠ new identity.** Rotation changes your *route*, not *you*. A site still
  knows you by your login, cookies, and browser fingerprint no matter how many times the
  exit IP flips.
- **UDP is never covered.** `proxychains` hooks TCP only — UDP and ICMP bypass even in
  `kernel` mode. Don't run `nmap -sU` or `ping` while believing you're hidden.
- **The human layer is yours.** Reused usernames, personal account logins, writing style,
  time-of-day habits — no proxy fixes those. Logging into Gmail through the chain just
  staples your identity to it.
- **Browser not included.** This tunnels connections; it does not normalise your
  fingerprint. Pair with **Tor Browser** for anything that matters.
- **VPN hop is optional and off by default.** Unless a host VPN interface is up, the chain
  is plain Tor (3 relays inside — guard/middle/exit).
- **Timing/volume correlation** (nation-state tier) is not defeated by any 5-minute rotation.

> **New route ≠ new identity.** This tool hardens the IP layer; accounts, browser, and
> behaviour are the other half — and they're on you.

## Config

- **Rotation interval:** menu option `7`, or `AXIOM_ROTATE=120 axiom`
- **VPN interface:** `AXIOM_VPN_IF=tun0 axiom` (Linux/macOS; N/A on Windows)
- **Extra hops:** add entries to `[ProxyList]` in `~/.axiom/proxychains4.conf`
  (socks5 host port rows — each becomes another hop in the strict chain)
- **Logs:** `~/.axiom/stack.log` — rotation events, engage/disengage, leak verdicts

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **`Proxy mode: ⚠️ per-tool` on Kali** | `proxychains4` not installed. `sudo apt install proxychains4`, then press `1` |
| `proxychains4: command not found` | Install it: `sudo apt install proxychains4` |
| Desktop icon missing | Right-click the `.desktop` → *Allow Launching*, or just type `axiom` |
| Menu didn't auto-open in a new tab | Per-session marker already fired; type `axiom` to open on demand |
| Menu opens in *every* new tab | `XDG_SESSION_ID` unset. Set `export AXIOM_SESSION_KEY=1` in `~/.zshrc` |
| `VPN ❌` on the board | No VPN interface on the **host**. Expected if you run none — chain still works |
| `Leak check ❌ BUSTED` | Real IP == exit IP. Press `1` to re-gate, `3` to rotate |
| `Leak check ❓ UNKNOWN` | IP lookup services unreachable — network flake, not a verdict. Press `4` to retry |
| `ROTATION FAILED` in log | Control port didn't answer NEWNYM. Press `1` to re-engage |
| Engage takes ~10–30s | Leak gate retries on flaky networks — it's verifying, not hanging |
| Port 9050 already in use | A `systemctl` Tor owns it — the stack shifts to the next free port pair |
| Tor Browser stopped working | It shouldn't have. This stack only ever touches its own instance — see Security notes |
| Second menu window quits, chain stays up | **By design** — ownership lock. The chain belongs to the window that engaged it |
| Everything runs but nothing routes | Press `1` to engage, then check the board: Tor + Rotator must both be ✅ |

## Uninstall

```bash
rm -rf ~/.axiom
rm -f ~/Desktop/AXIOM-Connect.desktop ~/.local/share/applications/axiom-connect.desktop
rm -f ~/Desktop/AXIOM-Connect.command ~/Desktop/AXIOM-Connect.cmd
# then delete the AXIOM auto-boot block + alias axiom line from ~/.zshrc and ~/.bashrc
```

---

## ⚠️ Disclaimer & Liability

**EDUCATIONAL AND INFORMATIONAL PURPOSES ONLY.**

This repository and its contents exist solely to demonstrate, document, and teach
networking and systems concepts — specifically Tor circuit management, SOCKS proxy routing,
IP-leak detection, process lifecycle management, and portable Bash scripting. It is **not**
anonymity software in any commercial or security-assurance sense, and it must not be relied
upon to conceal illegal activity.

By downloading, installing, copying, modifying, or running any part of this project, you
expressly acknowledge and agree to all of the following:

**1. Sole responsibility.** You are the only party responsible for how this software is used.
Any illegal, unlawful, harmful, abusive, deceptive, harassing, privacy-invasive, or otherwise
misuse — including any activity that infringes the rights of others — is entirely your own
doing and was not authorised, requested, or endorsed by the author.

**2. No liability — to the maximum extent permitted by law.** The author, contributors,
maintainers, and the GitHub organisation or entity hosting this repository accept **no
liability whatsoever** for any direct, indirect, incidental, consequential, special,
exemplary, or punitive damages, including but not limited to: data loss or breach, financial
loss, account suspension or termination, service or network bans, IP bans, loss of anonymity,
detection or deanonymisation, legal action, fines, prosecution, criminal conviction, civil
liability, employment or academic consequences, censorship, hardware damage, or loss of
profit. **No GitHub account, repository, or third-party platform bears responsibility for any
consequence arising from the use of this software.**

**3. No warranty.** The software is provided **"AS IS"**, without warranty of any kind,
express or implied, including but not limited to the warranties of merchantability, fitness
for a particular purpose, title, and non-infringement. It may contain bugs, defects, and
incomplete platform support. Verify it independently before relying on it.

**4. Compliance with law and terms of service.** Anonymity, proxy, and circumvention tools
are restricted, licensed, or entirely illegal in certain countries, and their use frequently
violates the terms of service of internet providers, employers, schools, universities,
examiners, and hosting providers. **You are solely responsible for determining whether your
use is lawful and permitted in your jurisdiction and under any agreement you have entered
into.** Do not use this software if you are unsure.

**5. No guarantee of anonymity or privacy.** A new circuit is not a new identity. This
project hardens the network/IP layer only. It does not defeat browser fingerprinting, account
or credential correlation, metadata leakage, timing and volume analysis, traffic-pattern
analysis, or any form of behavioural or nation-state level attribution. **Do not use this to
conceal criminal conduct, evade law enforcement, or infringe on anyone else's rights.**

**6. Security responsibility.** You are responsible for the security of any system on which
you install this software, including patching, access control, and protecting the
`~/.axiom` state directory (which holds a Tor control-authentication cookie readable by
your user account).

**7. Contribution to harm.** Any deployment of this software in a manner that causes harm to
individuals, organisations, critical infrastructure, or public safety is a misuse of the
project, and the author disclaims all association with, endorsement of, and responsibility
for such deployment.

**Intended audience.** Network engineers, security researchers, students, and developers
studying anonymisation networks, proxy chaining, and defensive systems security, operating
solely on systems they own or have explicit written authorisation to test.

**If you are unsure whether a use is lawful, do not perform it.**

## Credits

Original concept and Kali/Linux implementation by **CY3ER-CAT**. The macOS + Windows port
(found in this repository's history) added: `axiom-lib.sh` platform abstraction,
cookie-authenticated control port, collision-free dedicated Tor instances, and per-OS
process/launcher handling.

## License

MIT — see [LICENSE](LICENSE).

---

**Reminder:** rotating a circuit changes your route, not your identity. Accounts, browsers,
and behaviour are the other half — and they are on you. Use responsibly.