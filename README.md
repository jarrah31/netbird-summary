# netbird-summary

A bash script that parses `netbird status --detail` and displays a concise, color-coded peer connection summary table — and checks for (and installs) NetBird client updates.

Instead of scrolling through verbose multi-line output for each peer, get a single table showing every peer's status at a glance.

## Example Output

```
  NetBird Peer Connection Summary
  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
    PEER                                 NETBIRD IP         STATUS       TYPE      ICE (L/R)      LAST HANDSHAKE           LATENCY
  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  ● office-server                        100.10.0.1         Connected    P2P       srflx/srflx    Less than a second ago   10.518ms
  ● home-nas                             100.10.0.2         Connected    P2P       host/host      3 seconds ago            1.204ms
  ● cloud-vps                            100.10.0.3         Connected    Relayed   relay/relay    12 seconds ago           85.33ms
  ● laptop-backup                        100.10.0.4         Disconnected —         —              —                        —
  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  Legend:  ● P2P (direct)   ● Relayed   ● Disconnected/Connecting

  ICE candidate types (Local/Remote):
    host   — direct LAN address; both sides on same network or no NAT
    srflx  — server-reflexive; public IP discovered via STUN (most common, still P2P)
    prflx  — peer-reflexive; address discovered mid-handshake (peer-to-peer, slightly indirect)
    relay  — TURN relay in use; traffic is not peer-to-peer
    -      — not yet negotiated (connecting or relayed with no ICE path)

  This peer IP:       100.10.0.5
  Peers connected:    3/4
  Management:         https://api.netbird.io:443
  Daemon version:     0.36.5
```

## Columns

| Column | Description |
|---|---|
| **Peer** | Peer hostname |
| **NetBird IP** | The peer's WireGuard IP on the NetBird network |
| **Status** | `Connected` or `Disconnected` |
| **Type** | `P2P` (direct) or `Relayed` (via TURN server) |
| **ICE (L/R)** | Local/Remote ICE candidate types used for the connection |
| **Last Handshake** | Time since the last WireGuard handshake |
| **Latency** | Round-trip latency to the peer |

## Status Indicators

- 🟢 **Green** — Connected via P2P (direct)
- 🟡 **Yellow** — Connected but relayed (traffic goes through a TURN server)
- 🔴 **Red** — Disconnected or connecting

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

> This updates the **netbird-summary** script itself. To update the **NetBird client**, use option `2` in the menu (or `netbird-summary --update`).

## Usage

Run with no arguments to get an interactive menu (single keypress — no Enter needed):

```bash
netbird-summary
```

```
  NetBird Summary
  ───────────────
    1  Peer connection summary
    2  Check for client updates
    q  Quit

  Select an option:
```

Or jump straight to an action with a flag:

```bash
netbird-summary -s   # or --summary : show the peer connection summary
netbird-summary -u   # or --update  : check for updates and offer to upgrade
netbird-summary -h   # or --help    : show usage
```

When the output is piped or run non-interactively (e.g. from cron), the menu is skipped and the summary is printed directly — so existing scripts and symlinks keep working.

## Checking for updates

Option **2** (or `--update`) compares your installed client version (`netbird version`) against the latest release published on [NetBird's GitHub](https://github.com/netbirdio/netbird/releases) and tells you whether you're up to date.

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
