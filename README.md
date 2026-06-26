# netbird-summary

A bash script that turns `netbird status --detail` into a concise, color-coded peer connection summary — and can also show **which devices, resources and ports the current peer is allowed to reach** (and who can reach it) by querying the NetBird management API. It also checks for and installs NetBird client updates.

Instead of scrolling through verbose multi-line output for each peer, get a single table showing every peer's status at a glance.

## Example Output

### Peer summary

By default the summary lists **connected** peers in detail, hides idle/connecting peers behind a one-line note, and ends with a stats line:

```
  NetBird Peer Connection Summary
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
    PEER                           NETBIRD IP       TYPE   ICE (L/R)    REMOTE ENDPOINT       RX / TX         HANDSHAKE LATENCY
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  ● office-server                  100.10.0.1       P2P    host/host    203.0.113.10:42508    4.3K/7.2K       37s       15.27ms
  ● home-nas                       100.10.0.2       P2P    host/prflx   192.168.1.40:51820    4.4K/7.3K       7s        2.81ms
  ● cloud-vps                      100.10.0.3       Relayed relay/relay  -                     85.0K/64.0K     12s       85.33ms
  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  1 idle/connecting peer(s) hidden — see --all.

  Legend:  ● P2P (direct)   ● Relayed   ● Idle/Connecting

  ICE candidate types (Local/Remote):
    host   — direct LAN address; both sides on same network or no NAT
    srflx  — server-reflexive; public IP discovered via STUN (most common, still P2P)
    prflx  — peer-reflexive; address discovered mid-handshake (peer-to-peer, slightly indirect)
    relay  — TURN relay in use; traffic is not peer-to-peer
    -      — not yet negotiated (connecting or relayed with no ICE path)

  This peer IP:   100.10.0.5
  Peers:          12 total · 2 connected (1 P2P, 1 relayed) · 1 idle · 9 reverse-proxy (1 up)
  Management:     Connected to https://nb.example.com:443
  Daemon version: 0.73.2
```

Reverse-proxy / ingress peers (auto-named `proxy-…`) are kept out of every table to reduce clutter; only their count appears in the stats line. Press `3` (or `--all`) to list idle/connecting peers, each with how long they've been in that state.

### Access policy (`2` or `--access`)

Shows what this peer can reach **out**bound and who can reach it **in**bound, derived from your NetBird access-control policies via the API:

```
  NetBird Access Policy
  This peer: 100.10.0.5/16
  API:       https://nb.example.com:443/api

  Fetching peers, groups, policies and network resources…
  Member of groups: Admins, Workstations

  Access policy for laptop-01
  out: peer → endpoint   in: endpoint → peer
  DIR  POLICY          ENDPOINT          ADDRESS          PROTO  PORTS
  ──────────────────────────────────────────────────────────────────────────
  out  Web Apps      ● app-server      100.10.0.20      TCP    80, 443

  out  Home Router   ◆ router          192.168.1.1/32   TCP    443, 8443

  out  Database        Servers (2)                       TCP    5432
                     ● app-server      100.10.0.20
                     ● db-primary      100.10.0.21

  in   SSH Admin       Admins (1)                        TCP    22
                     ● jump-box        100.10.0.9
  ──────────────────────────────────────────────────────────────────────────
  out peer → endpoint   in endpoint → peer    ● online  ● offline  ◆ host/subnet
```

| Column | Description |
|---|---|
| **DIR** | `out` = this peer initiates to the endpoint · `in` = the endpoint initiates to this peer |
| **POLICY** | The access-control policy that grants the access |
| **ENDPOINT** | The other end: a single peer (`●`), a whole group (its members are listed beneath), or a host/subnet network resource (`◆`) |
| **ADDRESS** | The endpoint's NetBird IP, or a resource's address (e.g. a `/32` host or a subnet) |
| **PROTO / PORTS** | Protocol and the allowed ports (`all` when the policy isn't port-restricted) |

A peer can appear as both `out` and `in` for the same policy when it sits on both sides. The system **All** group (which contains every peer) is used for matching but hidden from the *Member of groups* line since it's not informative.

The table is **width-aware**: on a wide terminal everything fits on one line; as the window narrows the ports column wraps first, then the policy/endpoint names shorten, so nothing ever overflows the terminal.

> See [Access control (API access)](#access-control-api-access) for how the API token is requested and stored.

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

**Idle / connecting peers** (shown with `3` or `--all`) list **Peer**, **NetBird IP**, **Status**, and **For** (how long the peer has been in its current state — a large value usually means it's offline).

## Status Indicators

- 🟢 **Green** — Connected via P2P (direct)
- 🟡 **Yellow** — Connected but relayed (traffic goes through a TURN server)
- 🔵 **Cyan** — Connected, connection type not yet known
- 🔴 **Red** — Idle, connecting, or disconnected

> **About `proxy-…` peer names and stuck "Connecting" status:** NetBird auto-generates a hostname (e.g. `proxy-<id>-<ip>`) when a peer registers without a meaningful one. Rename peers in the NetBird dashboard to get friendly names here. These reverse-proxy / ingress peers are filtered out of the tables (a fresh one registers each time the proxy reconnects, so they pile up as stale "Connecting" entries) — only their count shows in the stats line. A normal peer that stays "Connecting" with a large **For** time is typically offline/unreachable, or an on-demand (lazy-connection) peer that only links up when there's traffic.

## Requirements

- [NetBird](https://netbird.io/) installed and running (`netbird status --detail` must work)
- Bash 3.2+ (macOS default is fine)
- `curl` — used for the update check and the access-policy API calls
- `python3` — **only** for the access-policy view (standard library only, no pip packages needed)

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

## Access control (API access)

The **access policy** view (`2` / `--access`) needs read access to your NetBird management API.

- **On first use** it prompts for a **NetBird API token**. Create one in the dashboard under **Settings → API Keys** — a read-only service user is enough.
- The token is saved to `~/.config/netbird-summary/api_key` with `600` permissions, and the management API URL is auto-detected from `netbird status` and cached at `~/.config/netbird-summary/api_url`. (Both honor `XDG_CONFIG_HOME`.)
- If the token is later **rejected** (for example it has expired or been revoked, returning HTTP 401/403), the script says so and prompts for a replacement, then retries. Connection failures and other errors get their own distinct messages.
- To **reset** the stored credentials, delete the directory:

  ```bash
  rm -rf ~/.config/netbird-summary
  ```

Under the hood it reads `/peers`, `/groups`, `/policies` and `/networks/resources`, then works out — for every **enabled** policy rule — where this peer sits (as a source and/or destination, whether via group membership or a direct peer/resource reference) and what that grants in each direction.

## Usage

Run with no arguments. It prints the summary immediately, then shows a single-keypress action prompt (no Enter needed):

```bash
netbird-summary
```

```
  ...summary table and stats...

  Actions:  1 summary   2 access policy   3 idle peers   a client update   b script update   q quit
```

| Key | Action |
|---|---|
| `1` | Re-print the peer summary |
| `2` | Show the **access policy** (devices/ports this peer can reach, and who can reach it) |
| `3` | List idle / connecting peers |
| `a` | Check for **NetBird client** updates |
| `b` | Check for **netbird-summary script** updates now (ignores the once/day throttle) |
| `q` | Quit |

The prompt loops after each action until you press `q`.

Or jump straight to an action with a flag:

```bash
netbird-summary -s   # or --summary : connected peers + stats only
netbird-summary -a   # or --all     : also list idle / connecting peers
netbird-summary -A   # or --access  : show the access policy (needs an API token)
netbird-summary -u   # or --update  : check for client updates and offer to upgrade
netbird-summary -h   # or --help    : show usage
```

> Note `-a` / `--all` (idle peers) and `-A` / `--access` (access policy) differ only by case.

When the output is piped or run non-interactively (e.g. from cron), the action prompt is skipped and only the summary is printed — so existing scripts and symlinks keep working.

### Hidden peer categories

By default the summary shows only **connected, non-proxy** peers. Two categories are kept out to keep it clean:

- **Idle / connecting** peers — a one-line note reports how many; list them with `3` or `--all`.
- **Reverse-proxy peers** — NetBird's [reverse-proxy / ingress](https://docs.netbird.io/manage/reverse-proxy) peers (auto-named `proxy-…`). A fresh one registers each time the proxy reconnects, so these pile up as stale "Connecting" entries with only the newest actually up. They're filtered out of every table; only their count appears in the stats line.

## Updating netbird-summary

To pull the latest version of this script from GitHub, run `git pull` inside the cloned repository:

```bash
cd /path/to/netbird-summary
git pull
```

If you set up a symlink during installation, you don't need to do anything else — the symlink points at the script in the repo, so it picks up the update automatically.

### Automatic update check

When run interactively, `netbird-summary` also checks GitHub for newer commits of **itself** and, if you're behind, offers to `git pull`:

```
  netbird-summary update available — 2 new commit(s) on GitHub
  /home/you/.local/share/netbird-summary
  Update netbird-summary now (git pull)? [y/N]
```

- The check is **throttled to at most once per day** and runs only when the script lives in a git checkout (i.e. installed via the one-liner or `git clone`). Press **`b`** at the action prompt to force a check immediately (handy when you've pushed several updates in one day) — this ignores the throttle and the disable switch.
- It's silent when you're up to date, offline, or throttled, and never blocks for long (a slow network aborts the check).
- Updates are fast-forward only; if you have local changes it tells you to pull manually.
- After a **successful** update the script **quits automatically** — the copy already running is the previous version and a shell script can't reload its own code mid-run, so it exits and asks you to re-run `netbird-summary` to use the new version.

Environment variables:

| Variable | Effect |
|---|---|
| `NETBIRD_SUMMARY_NO_SELFCHECK=1` | Disable the automatic self-update check entirely |
| `NETBIRD_SUMMARY_CHECK_INTERVAL_MIN=<n>` | Minimum minutes between checks (default `1440`) |

> This updates the **netbird-summary** script itself. To update the **NetBird client**, press `a` at the action prompt (or `netbird-summary --update`).

## Checking for client updates

Pressing **`a`** (or `--update`) compares your installed client version (`netbird version`) against the latest release published on [NetBird's GitHub](https://github.com/netbirdio/netbird/releases) and tells you whether you're up to date.

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

> **Note:** the GitHub version check is only performed when you choose the update option, and the access-policy API calls only run when you choose that view — normal summary runs stay fast and make no network calls.

## License

MIT
