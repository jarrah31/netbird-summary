# netbird-summary

A bash script that parses `netbird status --detail` and displays a concise, color-coded peer connection summary table.

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

## Usage

Simply run the script — no arguments needed:

```bash
netbird-summary
```

The script calls `netbird status --detail` and formats the output into a summary table.

## License

MIT
