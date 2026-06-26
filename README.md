# netbird-summary

A bash script that parses `netbird status --detail` and displays a concise, color-coded peer connection summary table — and checks for (and installs) NetBird client updates.

Instead of scrolling through verbose multi-line output for each peer, get a single table showing every peer's status at a glance.

## Example Output

By default the summary lists **connected, non-proxy** peers in detail, hides idle/connecting and reverse-proxy peers behind a one-line note, and ends with a stats line:

```
  NetBird Peer Connection Summary
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
    PEER                           NETBIRD IP       TYPE   ICE (L/R)    REMOTE ENDPOINT       RX / TX         HANDSHAKE LATENCY
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  ● office-server                  100.10.0.1       P2P    host/host    203.0.113.10:42508    4.3K/7.2K       37s       15.27ms
  ● home-nas                       100.10.0.2       P2P    host/prflx   192.168.1.40:51820    4.4K/7.3K       7s        2.81ms
  ● cloud-vps                      100.10.0.3       Relayed relay/relay  -                     85.0K/64.0K     12s       85.33ms
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  1 idle/connecting and 9 reverse-proxy peer(s) hidden — see --all / --proxy.

  Legend:  ● P2P (direct)   ● Relayed   ● Idle/Connecting

  ICE candidate types (Local/Remote):
    host   — direct LAN address; both sides on same network or no NAT
    srflx  — server-reflexive; public IP discovered via STUN (most common, still P2P)
    prflx  — peer-reflexive; address discovered mid-handshake (peer-to-peer, slightly indirect)
    relay  — TURN relay in use; traffic is not peer-to-peer
    -      — not yet negotiated (connecting or relayed with no ICE path)

  This peer IP:   100.10.0.5
  Peers:          12 total · 2 connected (1 P2P, 1 relayed) · 1 idle · 9 reverse-proxy (1 up)
  Management:     Connected to https://api.netbird.io:443
  Daemon version: 0.73.2
```

Press `2` (or `--all`) to list idle/connecting peers, or `3` (or `--proxy`) for reverse-proxy peers, each with how long they've been in that state:

```
  Reverse-proxy peers  (9)
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────
    PEER                                         NETBIRD IP       STATUS       TYPE     REMOTE ENDPOINT       FOR
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────
  ● proxy-d8lh86r95s1s73dm1big-70-123.netbird.… 100.124.70.123   Connecting   -        -                     2h12m
  ● proxy-d8u48hj95s1s739icub0-204-116.netbird… 100.124.204.116  Connected    Relayed  -                     2h12m
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────
  NetBird Reverse Proxy / ingress peers. A new one registers each time the proxy
  reconnects; usually only the newest is Connected and the others are stale leftovers.
```

## Columns

**Connected peers table:**

| Column | Description |
|---|---|
| **Peer** | Peer hostname / FQDN (set this in the NetBird dashboard for friendly names) |
| **NetBird IP** | The peer's WireGuard IP on the NetBird network |
| **Type** | `P2P` (direct) or `Relayed` (via TURN server) |
| **ICE (L/R)** | Local/Remote ICE candidate types used for the connection |
| **Remote Endpoint** | The peer's real IP:port the tunnel connects to |
| **RX / TX** | Data received / sent over the tunnel |
| **Handshake** | Time since the last WireGuard handshake |
| **Latency** | Round-trip latency to the peer |

**Idle / connecting peers** (shown with `--all`) list **Peer**, **NetBird IP**, **Status**, and **For** (how long the peer has been in its current state — a large value usually means it's offline). **Reverse-proxy peers** (shown with `--proxy`) additionally show **Type** and **Remote Endpoint**.

## Status Indicators

- 🟢 **Green** — Connected via P2P (direct)
- 🟡 **Yellow** — Connected but relayed (traffic goes through a TURN server)
- 🔵 **Cyan** — Connected, connection type not yet known
- 🔴 **Red** — Idle, connecting, or disconnected

> **About `proxy-…` peer names and stuck "Connecting" status:** NetBird auto-generates a hostname (e.g. `proxy-<id>-<ip>`) when a peer registers without a meaningful one. Rename peers in the NetBird dashboard to get friendly names here. A peer that stays "Connecting" with a large **For** time is typically offline/unreachable, or an on-demand (lazy-connection) peer that only links up when there's traffic.

## Requirements

- [NetBird](https://netbird.io/) installed and running (`netbird status --detail` must work)
- Bash 3.2+ (macOS default is fine)

## Installation

### Quick install (recommended)

Copy and paste this one-liner. It detects your OS, clones the repo from GitHub, symlinks the `netbird-summary` command into the right bin directory, and adds it to your PATH:

```bash
curl -fsSL https://raw.githubusercontent.com/jarrah31/netbird-summary/main/install.sh | bash
```

What it does:

- Clones into `~/.local/share/netbird-summary` (override with `NETBIRD_SUMMARY_DIR`)
- Symlinks the command into a bin directory chosen for your OS (override with `NETBIRD_SUMMARY_BIN`):
  - **macOS / Linux** — `/usr/local/bin` if writable, otherwise `~/.local/bin`
  - **Windows (Git Bash / MSYS2)** — `~/bin`
- Appends a `PATH` line to your shell profile (`~/.zshrc`, `~/.bashrc`, or `~/.profile`) only if the bin directory isn't already on PATH

Re-running the one-liner later updates an existing install (`git pull`). Requires `git`.

> Prefer to read before you pipe to a shell? View the script first: [install.sh](install.sh).

After installing, open a new terminal (or `source` the profile it mentions) and run `netbird-summary`.

### Manual install

Clone the repository:

```bash
git clone https://github.com/jarrah31/netbird-summary.git
cd netbird-summary
chmod +x netbird-summary.sh
```

### Adding to PATH via symlink

Create a symbolic link so you can run `netbird-summary` from anywhere.

**macOS / Linux:**

```bash
ln -s "$(pwd)/netbird-summary.sh" /usr/local/bin/netbird-summary
```

If `/usr/local/bin` doesn't exist or isn't in your PATH, you can use `~/.local/bin` instead:

```bash
mkdir -p ~/.local/bin
ln -s "$(pwd)/netbird-summary.sh" ~/.local/bin/netbird-summary
```

Then ensure `~/.local/bin` is in your PATH by adding this to your `~/.bashrc`, `~/.zshrc`, or equivalent:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Windows (WSL):**

From within your WSL shell, follow the same Linux instructions above.

**Windows (Git Bash / MSYS2):**

```bash
ln -s "$(pwd)/netbird-summary.sh" ~/bin/netbird-summary
```

Ensure `~/bin` is in your PATH. Git Bash typically includes it by default.

### Verify

```bash
netbird-summary
```

## Updating netbird-summary

To pull the latest version of this script from GitHub, run `git pull` inside the cloned repository:

```bash
cd /path/to/netbird-summary
git pull
```

If you set up a symlink during installation, you don't need to do anything else — the symlink points at the script in the repo, so it picks up the update automatically.

> This updates the **netbird-summary** script itself. To update the **NetBird client**, press `1` at the action prompt (or `netbird-summary --update`).

## Usage

Run with no arguments. It prints the summary immediately, then shows a single-keypress action prompt (no Enter needed):

```bash
netbird-summary
```

```
  ...summary table and stats...

  Actions:  1 update check   2 idle peers   3 proxy peers   s summary   q quit
```

| Key | Action |
|---|---|
| `1` | Check for client updates |
| `2` | List idle / connecting peers |
| `3` | List reverse-proxy peers |
| `s` | Re-print the summary |
| `q` | Quit |

The prompt loops after each action until you press `q`.

Or jump straight to an action with a flag:

```bash
netbird-summary -s   # or --summary : connected peers + stats only
netbird-summary -a   # or --all     : also list idle / connecting peers
netbird-summary -p   # or --proxy   : also list reverse-proxy peers
netbird-summary -u   # or --update  : check for updates and offer to upgrade
netbird-summary -h   # or --help    : show usage
```

When the output is piped or run non-interactively (e.g. from cron), the action prompt is skipped and only the summary is printed — so existing scripts and symlinks keep working.

### Hidden peer categories

By default the summary shows only **connected, non-proxy** peers. Two categories are hidden to keep it clean (a one-line note reports how many):

- **Idle / connecting** peers — list them with `2` or `--all`.
- **Reverse-proxy peers** — NetBird's [reverse-proxy / ingress](https://docs.netbird.io/manage/reverse-proxy) peers (auto-named `proxy-…`). A fresh one registers each time the proxy reconnects, so these tend to pile up as stale "Connecting" entries with only the newest actually up. List them with `3` or `--proxy`.

## Checking for updates

Pressing **`1`** (or `--update`) compares your installed client version (`netbird version`) against the latest release published on [NetBird's GitHub](https://github.com/netbirdio/netbird/releases) and tells you whether you're up to date.

If a newer version is available **on Linux**, the script offers to upgrade you. It detects how NetBird was installed and uses the matching method:

| Detected install | Update command used |
|---|---|
| APT package + NetBird repo | `sudo apt-get update && sudo apt-get install -y netbird` |
| RPM package + NetBird repo (`dnf`) | `sudo dnf install -y netbird` |
| RPM package + NetBird repo (`yum`) | `sudo yum install -y netbird` |
| Anything else | `netbird down` → official [`install.sh --update`](https://docs.netbird.io/get-started/install/linux#updating) → `netbird up` |

A package manager is only used when it **both** manages the `netbird` package **and** has the official NetBird repo (`pkgs.netbird.io`) configured — so it can actually fetch the new version. This is the normal case for the `curl … install.sh | sh` one-liner, which adds that repo and installs via apt/yum/dnf on supported distros. Anything else (a manually-installed `.deb`/`.rpm` without the repo, or a plain binary install) falls back to the official install script, which re-adds the repo and self-heals.

The exact commands are shown and require a single-key `y` confirmation before anything runs. `sudo` is used automatically when you're not root.

On macOS the update check still reports your version status, but upgrades are left to your original install method (e.g. `brew upgrade netbird` or the `.pkg` installer).

> **Note:** the GitHub version check is only performed when you choose the update option — normal summary runs stay fast and make no network calls.

## License

MIT
