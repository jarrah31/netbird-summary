#!/usr/bin/env bash
# netbird-summary — concise peer connection summary + update checker
# Compatible with bash 3.2+ (macOS default)

BOLD=$'\033[1m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
CYAN=$'\033[36m'
DIM=$'\033[2m'
RESET=$'\033[0m'

GITHUB_LATEST_API="https://api.github.com/repos/netbirdio/netbird/releases/latest"
INSTALL_SCRIPT_URL="https://pkgs.netbird.io/install.sh"

# Truncate a string to max chars, appending … if trimmed
trunc() {
    local s="$1" max="$2"
    (( ${#s} > max )) && printf '%s' "${s:0:$((max-1))}…" || printf '%s' "$s"
}

# ════════════════════════════════════════════════════════════════════════════════
#  Peer connection summary
# ════════════════════════════════════════════════════════════════════════════════
# Abbreviate a NetBird duration ("58 minutes, 19 seconds ago") → "58m19s"
abbr_dur() {
    local s="$1" out=""
    case "$s" in
        ""|"-")             printf '%s' "-";   return ;;
        Less\ than*|*less\ than*) printf '%s' "<1s"; return ;;
    esac
    [[ "$s" =~ ([0-9]+)\ day    ]] && out+="${BASH_REMATCH[1]}d"
    [[ "$s" =~ ([0-9]+)\ hour   ]] && out+="${BASH_REMATCH[1]}h"
    [[ "$s" =~ ([0-9]+)\ minute ]] && out+="${BASH_REMATCH[1]}m"
    [[ "$s" =~ ([0-9]+)\ second ]] && out+="${BASH_REMATCH[1]}s"
    [[ -z "$out" ]] && out="$s"
    printf '%s' "$out"
}

# Abbreviate "3.8 KiB/6.3 KiB" → "3.8K/6.3K"
abbr_bytes() {
    local s="$1"
    [[ -z "$s" || "$s" == "-" ]] && { printf '%s' "-"; return; }
    s="${s// /}"      # drop spaces
    s="${s//iB/}"     # KiB→K, MiB→M, GiB→G (a lone B stays B)
    printf '%s' "$s"
}

# Round a latency value ("5.376674ms") → "5.38ms"; pass through if unparsable
abbr_lat() {
    local s="$1" num rest
    [[ -z "$s" || "$s" == "-" ]] && { printf '%s' "-"; return; }
    num="${s%%[!0-9.]*}"
    rest="${s#"$num"}"
    if [[ -n "$num" && -n "$rest" ]]; then
        printf '%.2f%s' "$num" "$rest"
    else
        printf '%s' "$s"
    fi
}

# ── Shared parsed peer data (populated by parse_peers) ──────────────────────────
g_names=(); g_ips=(); g_statuses=(); g_types=(); g_ices=()
g_ends=(); g_txs=(); g_shakes=(); g_lats=(); g_fors=()
g_raw=""

# A reverse-proxy / ingress peer — NetBird names them "proxy-<id>-<octets>"
is_proxy() { [[ "$1" == proxy-* ]]; }

# Run `netbird status --detail` and populate the g_* arrays. Returns 1 on error.
parse_peers() {
    if ! g_raw=$(netbird status --detail 2>&1); then
        printf 'Error running netbird status --detail:\n%s\n' "$g_raw" >&2
        return 1
    fi

    g_names=(); g_ips=(); g_statuses=(); g_types=(); g_ices=()
    g_ends=(); g_txs=(); g_shakes=(); g_lats=(); g_fors=()

    local p_name p_ip p_status p_type p_ice p_end p_tx p_shake p_lat p_for line
    _reset_peer() {
        p_name=""; p_ip="-"; p_status="-"; p_type="-"; p_ice="-"
        p_end="-"; p_tx="-"; p_shake="-"; p_lat="-"; p_for="-"
    }
    _flush_peer() {
        [[ -z "$p_name" ]] && return
        g_names+=("$p_name");   g_ips+=("$p_ip");       g_statuses+=("$p_status")
        g_types+=("$p_type");   g_ices+=("$p_ice");     g_ends+=("$p_end")
        g_txs+=("$p_tx");       g_shakes+=("$p_shake"); g_lats+=("$p_lat"); g_fors+=("$p_for")
    }
    _reset_peer

    while IFS= read -r line; do
        # Peer header: one leading space, name (not starting with - or :), ends with colon
        if [[ "$line" =~ ^[[:space:]]([^[:space:]:-][^:]*):$ ]]; then
            _flush_peer; _reset_peer; p_name="${BASH_REMATCH[1]}"
        elif [[ -z "$p_name" ]]; then
            continue
        elif [[ "$line" =~ ^[[:space:]]+NetBird\ IP:\ (.+)$ ]]; then
            p_ip="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+Status:\ (.+)$ ]]; then
            p_status="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+Connection\ type:\ (.+)$ ]]; then
            p_type="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+ICE\ candidate\ endpoints\ \(Local/Remote\):\ (.+)$ ]]; then
            p_end="${BASH_REMATCH[1]#*/}"   # remote half (after the slash)
        elif [[ "$line" =~ ^[[:space:]]+ICE\ candidate\ \(Local/Remote\):\ (.+)$ ]]; then
            p_ice="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+Last\ connection\ update:\ (.+)$ ]]; then
            p_for="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+Last\ [Ww]ire[Gg]uard\ handshake:\ (.+)$ ]]; then
            p_shake="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+Transfer\ status\ \(received/sent\)\ (.+)$ ]]; then
            p_tx="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]+Latency:\ (.+)$ ]]; then
            p_lat="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^(Events:|OS:) ]]; then
            _flush_peer; _reset_peer
        fi
    done <<< "$g_raw"
    _flush_peer  # catch last peer if output ended without Events:/OS:
}

# Connected, non-proxy peers — the main table.
render_connected() {
    local cN=30 cI=16 cT=6 cE=12 cP=21 cX=15 cH=9 cL=11
    local tot=$(( cN + cI + cT + cE + cP + cX + cH + cL + 11 ))
    local SEP; SEP=$(printf '─%.0s' $(seq 1 "$tot"))
    local rowfmt='  %s %-'"$cN"'s %-'"$cI"'s %-'"$cT"'s %-'"$cE"'s %-'"$cP"'s %-'"$cX"'s %-'"$cH"'s %s\n'

    printf '\n  %s%sNetBird Peer Connection Summary%s\n' "$BOLD" "$CYAN" "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
    printf '  %s  %-'"$cN"'s %-'"$cI"'s %-'"$cT"'s %-'"$cE"'s %-'"$cP"'s %-'"$cX"'s %-'"$cH"'s %s%s\n' \
        "$BOLD" \
        "PEER" "NETBIRD IP" "TYPE" "ICE (L/R)" "REMOTE ENDPOINT" "RX / TX" "HANDSHAKE" "LATENCY" \
        "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"

    local i ind shown=0
    for ((i=0; i<${#g_names[@]}; i++)); do
        is_proxy "${g_names[$i]}" && continue
        [[ "${g_statuses[$i]}" == Connected ]] || continue
        shown=$((shown+1))
        if   [[ "${g_types[$i]}" == P2P     ]]; then ind="${GREEN}●${RESET}"
        elif [[ "${g_types[$i]}" == Relayed ]]; then ind="${YELLOW}●${RESET}"
        else                                         ind="${CYAN}●${RESET}"
        fi
        printf "$rowfmt" "$ind" \
            "$(trunc "${g_names[$i]}"                   $cN)" \
            "$(trunc "${g_ips[$i]}"                     $cI)" \
            "$(trunc "${g_types[$i]}"                   $cT)" \
            "$(trunc "${g_ices[$i]}"                    $cE)" \
            "$(trunc "${g_ends[$i]}"                    $cP)" \
            "$(trunc "$(abbr_bytes "${g_txs[$i]}")"     $cX)" \
            "$(trunc "$(abbr_dur   "${g_shakes[$i]}")"  $cH)" \
            "$(trunc "$(abbr_lat   "${g_lats[$i]}")"    $cL)"
    done
    (( shown == 0 )) && printf '  %s  No connected peers.%s\n' "$DIM" "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
}

# Idle / connecting, non-proxy peers.
render_idle() {
    local dN=46 dI=16 dS=12
    local tot=$(( dN + dI + dS + 12 + 8 ))
    local SEP; SEP=$(printf '─%.0s' $(seq 1 "$tot"))
    local i n=0
    for ((i=0; i<${#g_names[@]}; i++)); do
        is_proxy "${g_names[$i]}" && continue
        [[ "${g_statuses[$i]}" == Connected ]] && continue
        n=$((n+1))
    done

    printf '\n  %s%sIdle / connecting peers%s  %s(%d)%s\n' "$BOLD" "$CYAN" "$RESET" "$DIM" "$n" "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
    printf '  %s  %-'"$dN"'s %-'"$dI"'s %-'"$dS"'s %s%s\n' \
        "$BOLD" "PEER" "NETBIRD IP" "STATUS" "FOR" "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
    if (( n == 0 )); then
        printf '  %s  No idle / connecting peers.%s\n' "$DIM" "$RESET"
    else
        for ((i=0; i<${#g_names[@]}; i++)); do
            is_proxy "${g_names[$i]}" && continue
            [[ "${g_statuses[$i]}" == Connected ]] && continue
            printf '  %s %-'"$dN"'s %-'"$dI"'s %-'"$dS"'s %s\n' \
                "${RED}●${RESET}" \
                "$(trunc "${g_names[$i]}"    $dN)" \
                "$(trunc "${g_ips[$i]}"      $dI)" \
                "$(trunc "${g_statuses[$i]}" $dS)" \
                "$(abbr_dur "${g_fors[$i]}")"
        done
    fi
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
    printf '  %sFOR = time since the connection state last changed; a large value usually means the peer is offline.%s\n' "$DIM" "$RESET"
}

# Reverse-proxy / ingress peers (any status).
render_proxy() {
    local cN=44 cI=16 cS=12 cT=8 cP=21
    local tot=$(( cN + cI + cS + cT + cP + 12 + 10 ))
    local SEP; SEP=$(printf '─%.0s' $(seq 1 "$tot"))
    local i n=0
    for ((i=0; i<${#g_names[@]}; i++)); do is_proxy "${g_names[$i]}" && n=$((n+1)); done

    printf '\n  %s%sReverse-proxy peers%s  %s(%d)%s\n' "$BOLD" "$CYAN" "$RESET" "$DIM" "$n" "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
    printf '  %s  %-'"$cN"'s %-'"$cI"'s %-'"$cS"'s %-'"$cT"'s %-'"$cP"'s %s%s\n' \
        "$BOLD" "PEER" "NETBIRD IP" "STATUS" "TYPE" "REMOTE ENDPOINT" "FOR" "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
    if (( n == 0 )); then
        printf '  %s  No reverse-proxy peers.%s\n' "$DIM" "$RESET"
    else
        local ind
        for ((i=0; i<${#g_names[@]}; i++)); do
            is_proxy "${g_names[$i]}" || continue
            if [[ "${g_statuses[$i]}" == Connected ]]; then ind="${GREEN}●${RESET}"
            else                                            ind="${RED}●${RESET}"
            fi
            printf '  %s %-'"$cN"'s %-'"$cI"'s %-'"$cS"'s %-'"$cT"'s %-'"$cP"'s %s\n' \
                "$ind" \
                "$(trunc "${g_names[$i]}"    $cN)" \
                "$(trunc "${g_ips[$i]}"      $cI)" \
                "$(trunc "${g_statuses[$i]}" $cS)" \
                "$(trunc "${g_types[$i]}"    $cT)" \
                "$(trunc "${g_ends[$i]}"     $cP)" \
                "$(abbr_dur "${g_fors[$i]}")"
        done
    fi
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
    printf '  %sNetBird Reverse Proxy / ingress peers. A new one registers each time the proxy\n' "$DIM"
    printf '  reconnects; usually only the newest is Connected and the others are stale leftovers.%s\n' "$RESET"
}

# Legend + ICE candidate reference.
render_legend() {
    printf '\n  %sLegend:%s  %s● P2P (direct)%s   %s● Relayed%s   %s● Idle/Connecting%s\n' \
        "$DIM" "$RESET" "$GREEN" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"

    printf '\n  %sICE candidate types (Local/Remote):%s\n' "$BOLD" "$RESET"
    printf '  %s  host%s   — direct LAN address; both sides on same network or no NAT\n'  "$GREEN"  "$RESET"
    printf '  %s  srflx%s  — server-reflexive; public IP discovered via STUN (most common, still P2P)\n' "$GREEN" "$RESET"
    printf '  %s  prflx%s  — peer-reflexive; address discovered mid-handshake (peer-to-peer, slightly indirect)\n' "$CYAN" "$RESET"
    printf '  %s  relay%s  — TURN relay in use; traffic is not peer-to-peer\n'             "$YELLOW" "$RESET"
    printf '  %s  -%s      — not yet negotiated (connecting or relayed with no ICE path)\n' "$RED"    "$RESET"
}

# Tally + system info line.
render_stats() {
    local total=${#g_names[@]} r_conn=0 r_p2p=0 r_relay=0 r_idle=0 prox=0 prox_up=0 i
    for ((i=0; i<total; i++)); do
        if is_proxy "${g_names[$i]}"; then
            prox=$((prox+1))
            [[ "${g_statuses[$i]}" == Connected ]] && prox_up=$((prox_up+1))
        elif [[ "${g_statuses[$i]}" == Connected ]]; then
            r_conn=$((r_conn+1))
            case "${g_types[$i]}" in
                P2P)     r_p2p=$((r_p2p+1)) ;;
                Relayed) r_relay=$((r_relay+1)) ;;
            esac
        else
            r_idle=$((r_idle+1))
        fi
    done

    local nb_ip profile daemon mgmt
    nb_ip=$(   awk '/^NetBird IP:/{print $3}'                   <<< "$g_raw")
    profile=$( awk '/^Profile:/{print $2}'                      <<< "$g_raw")
    daemon=$(  awk '/^Daemon version:/{print $3}'                <<< "$g_raw")
    mgmt=$(    awk '/^Management:/{$1=""; sub(/^ /,""); print}' <<< "$g_raw")

    printf '\n'
    printf '  %s%-16s%s%s\n' "$BOLD" "This peer IP:" "$RESET" "$nb_ip"
    printf '  %s%-16s%s%d total · %s%d connected%s (%d P2P, %d relayed) · %s%d idle%s · %s%d reverse-proxy%s (%d up)\n' \
        "$BOLD" "Peers:" "$RESET" "$total" \
        "$GREEN" "$r_conn" "$RESET" "$r_p2p" "$r_relay" \
        "$YELLOW" "$r_idle" "$RESET" "$CYAN" "$prox" "$RESET" "$prox_up"
    [[ -n "$profile" ]] &&
    printf '  %s%-16s%s%s\n' "$BOLD" "Profile:"        "$RESET" "$profile"
    printf '  %s%-16s%s%s\n' "$BOLD" "Management:"     "$RESET" "$mgmt"
    printf '  %s%-16s%s%s\n' "$BOLD" "Daemon version:" "$RESET" "$daemon"
    printf '\n'
}

# Default landing: connected peers + legend + stats, with idle/proxy hidden.
show_summary() {
    parse_peers || return 1
    render_connected

    local i idle=0 prox=0
    for ((i=0; i<${#g_names[@]}; i++)); do
        if is_proxy "${g_names[$i]}"; then prox=$((prox+1))
        elif [[ "${g_statuses[$i]}" != Connected ]]; then idle=$((idle+1))
        fi
    done
    if (( idle > 0 || prox > 0 )); then
        printf '\n  %s%d idle/connecting and %d reverse-proxy peer(s) hidden — see --all / --proxy.%s\n' \
            "$DIM" "$idle" "$prox" "$RESET"
    fi

    render_legend
    render_stats
}

# ════════════════════════════════════════════════════════════════════════════════
#  Update checking
# ════════════════════════════════════════════════════════════════════════════════

# Installed client version, e.g. "0.73.2" (leading "v" stripped). Empty if unknown.
get_current_version() {
    local v
    v=$(netbird version 2>/dev/null | head -1 | tr -d '[:space:]')
    printf '%s' "${v#v}"
}

# Latest release version from GitHub, e.g. "0.73.2". Empty on failure.
get_latest_version() {
    local json
    json=$(curl -fsSL --max-time 10 "$GITHUB_LATEST_API" 2>/dev/null) || return 1
    printf '%s\n' "$json" \
        | grep -m1 '"tag_name"' \
        | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/'
}

# Compare two versions → prints "equal", "older" (a < b) or "newer" (a > b)
version_compare() {
    local a="$1" b="$2" greatest
    if [[ "$a" == "$b" ]]; then echo equal; return; fi
    greatest=$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)
    if [[ "$greatest" == "$b" ]]; then echo older; else echo newer; fi
}

# Is the official NetBird APT repo configured?
netbird_apt_repo_present() {
    grep -rqs 'pkgs\.netbird\.io' \
        /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null
}

# Is the official NetBird YUM/DNF repo configured?
netbird_yum_repo_present() {
    grep -rqs 'pkgs\.netbird\.io' /etc/yum.repos.d/ 2>/dev/null
}

# Detect how netbird should be updated → "apt", "dnf", "yum", or "script".
#
# We trust a package manager only when it BOTH manages the netbird package and
# has the official NetBird repo configured (so it can actually fetch the new
# version). Otherwise — including a manually-installed .deb/.rpm with no repo —
# we fall back to the official install script, which re-adds the repo and
# self-heals. Note: the install script itself installs via apt/yum/dnf on those
# distros, so a package-managed install is the normal, expected result.
detect_install_method() {
    if command -v dpkg >/dev/null 2>&1 && dpkg -s netbird >/dev/null 2>&1 \
       && netbird_apt_repo_present; then
        echo apt
    elif command -v rpm >/dev/null 2>&1 && rpm -q netbird >/dev/null 2>&1 \
         && netbird_yum_repo_present; then
        if   command -v dnf >/dev/null 2>&1; then echo dnf
        elif command -v yum >/dev/null 2>&1; then echo yum
        else echo script
        fi
    else
        echo script   # binary install, or package present without the repo
    fi
}

# Single-keypress yes/no confirmation. Returns 0 for yes.
confirm() {
    local prompt="${1:-Proceed?}" ans
    printf '  %s [y/N] ' "$prompt"
    read -rsn1 ans
    printf '%s\n' "$ans"
    [[ "$ans" == y || "$ans" == Y ]]
}

# Run the upgrade using the detected install method.
run_update() {
    local method="$1"
    local SUDO=""
    if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
        SUDO="sudo "
    fi

    case "$method" in
        apt)
            printf '\n  %sInstalled via APT. The following will run:%s\n' "$DIM" "$RESET"
            printf '    %s%sapt-get update%s\n'            "$CYAN" "$SUDO" "$RESET"
            printf '    %s%sapt-get install -y netbird%s\n\n' "$CYAN" "$SUDO" "$RESET"
            confirm "Update NetBird via APT now?" || { printf '  Cancelled.\n'; return 1; }
            ${SUDO}apt-get update && ${SUDO}apt-get install -y netbird
            ;;
        dnf)
            printf '\n  %sInstalled via DNF. The following will run:%s\n' "$DIM" "$RESET"
            printf '    %s%sdnf install -y netbird%s\n\n' "$CYAN" "$SUDO" "$RESET"
            confirm "Update NetBird via DNF now?" || { printf '  Cancelled.\n'; return 1; }
            ${SUDO}dnf install -y netbird
            ;;
        yum)
            printf '\n  %sInstalled via YUM. The following will run:%s\n' "$DIM" "$RESET"
            printf '    %s%syum install -y netbird%s\n\n' "$CYAN" "$SUDO" "$RESET"
            confirm "Update NetBird via YUM now?" || { printf '  Cancelled.\n'; return 1; }
            ${SUDO}yum install -y netbird
            ;;
        script)
            printf '\n  %sInstalled via the official install script. The following will run:%s\n' "$DIM" "$RESET"
            printf '    %snetbird down%s\n'                          "$CYAN" "$RESET"
            printf '    %scurl -fsSL %s | %ssh -s -- --update%s\n'   "$CYAN" "$INSTALL_SCRIPT_URL" "$SUDO" "$RESET"
            printf '    %snetbird up%s\n\n'                          "$CYAN" "$RESET"
            confirm "Update NetBird via the install script now?" || { printf '  Cancelled.\n'; return 1; }

            local tmpd
            tmpd=$(mktemp -d 2>/dev/null) || { printf '  %sCould not create a temp directory.%s\n' "$RED" "$RESET"; return 1; }

            netbird down
            if curl -fsSL --max-time 60 -o "$tmpd/install.sh" "$INSTALL_SCRIPT_URL"; then
                chmod +x "$tmpd/install.sh"
                ${SUDO}"$tmpd/install.sh" --update
            else
                printf '  %sFailed to download the install script.%s\n' "$RED" "$RESET"
            fi
            netbird up
            rm -rf "$tmpd"
            ;;
        *)
            printf '  %sUnknown install method.%s\n' "$RED" "$RESET"
            return 1
            ;;
    esac
}

# Check for a newer version and, if found, offer to update (Linux only).
check_update() {
    printf '\n  %s%sNetBird Update Check%s\n\n' "$BOLD" "$CYAN" "$RESET"

    if ! command -v netbird >/dev/null 2>&1; then
        printf '  %sThe "netbird" command was not found in PATH.%s\n' "$RED" "$RESET"
        return 1
    fi

    local current latest
    current=$(get_current_version)
    if [[ -z "$current" ]]; then
        printf '  %sCould not determine the installed NetBird version.%s\n' "$RED" "$RESET"
        return 1
    fi
    printf '  %s%-20s%s%s\n' "$BOLD" "Installed version:" "$RESET" "$current"

    printf '  %sChecking latest release on GitHub…%s\n' "$DIM" "$RESET"
    latest=$(get_latest_version)
    if [[ -z "$latest" ]]; then
        printf '  %sCould not reach GitHub to check the latest version.%s\n' "$RED" "$RESET"
        return 1
    fi
    printf '  %s%-20s%s%s\n\n' "$BOLD" "Latest release:" "$RESET" "$latest"

    case "$(version_compare "$current" "$latest")" in
        equal)
            printf '  %s● You are running the latest version.%s\n' "$GREEN" "$RESET"
            return 0 ;;
        newer)
            printf '  %s● Your version is newer than the latest release (development build).%s\n' "$CYAN" "$RESET"
            return 0 ;;
    esac

    printf '  %s● A newer version is available: %s → %s%s\n' "$YELLOW" "$current" "$latest" "$RESET"

    local os
    os=$(uname -s)
    if [[ "$os" != Linux ]]; then
        printf '\n  Automated updates are only supported on Linux.\n'
        printf '  On %s, update NetBird with your original install method\n' "$os"
        printf '  (e.g. %sbrew upgrade netbird%s or the macOS .pkg installer).\n' "$BOLD" "$RESET"
        return 0
    fi

    run_update "$(detect_install_method)"
}

# ════════════════════════════════════════════════════════════════════════════════
#  Self-update (the netbird-summary script itself)
# ════════════════════════════════════════════════════════════════════════════════

# Resolve the directory of the real script, following symlinks (the install
# symlink points at netbird-summary.sh inside the cloned repo).
self_repo_dir() {
    local src="${BASH_SOURCE[0]}" dir
    while [ -h "$src" ]; do
        dir=$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)
        src=$(readlink "$src")
        [[ "$src" != /* ]] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# True if the throttled remote check is due (default: at most once per day).
_selfcheck_due() {
    local stamp="$1" maxmin="${NETBIRD_SUMMARY_CHECK_INTERVAL_MIN:-1440}"
    [[ -f "$stamp" ]] || return 0
    [[ -n "$(find "$stamp" -mmin +"$maxmin" 2>/dev/null)" ]]
}

# Auto-check GitHub for newer commits of THIS script and offer to git pull.
# Silent when up to date, offline, throttled, or not a git checkout.
# With "force": bypass the throttle (and the disable switch) and report the
# outcome even when up to date — used by the manual action-prompt option.
self_update_check() {
    local force="${1:-}"

    if [[ -n "${NETBIRD_SUMMARY_NO_SELFCHECK:-}" && "$force" != force ]]; then
        return 0
    fi
    if ! command -v git >/dev/null 2>&1; then
        [[ "$force" == force ]] && printf '  %sgit is not installed — cannot self-update.%s\n' "$RED" "$RESET"
        return 0
    fi

    local repo; repo=$(self_repo_dir)
    if [[ -z "$repo" || ! -d "$repo/.git" ]]; then
        [[ "$force" == force ]] && printf '  %sNot a git checkout — cannot self-update.%s\n' "$YELLOW" "$RESET"
        return 0
    fi

    local stamp="$repo/.git/.netbird-summary-checked"
    [[ "$force" == force ]] || _selfcheck_due "$stamp" || return 0
    touch "$stamp" 2>/dev/null                          # throttle regardless of result

    [[ "$force" == force ]] && printf '\n  %sChecking GitHub for netbird-summary updates…%s\n' "$DIM" "$RESET"

    # Lightweight fetch with a low-speed cutoff so a bad network can't hang us.
    if ! git -C "$repo" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5 \
            fetch --quiet origin >/dev/null 2>&1; then
        [[ "$force" == force ]] && printf '  %sCould not reach GitHub to check for updates.%s\n' "$RED" "$RESET"
        return 0
    fi

    local behind
    behind=$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null)
    if ! [[ "$behind" =~ ^[0-9]+$ ]] || (( behind == 0 )); then
        [[ "$force" == force ]] && printf '  %s● netbird-summary is up to date.%s\n' "$GREEN" "$RESET"
        return 0
    fi

    printf '\n  %s%snetbird-summary update available%s — %s%s%s new commit(s) on GitHub\n' \
        "$BOLD" "$CYAN" "$RESET" "$BOLD" "$behind" "$RESET"
    printf '  %s%s%s\n' "$DIM" "$repo" "$RESET"
    if confirm "Update netbird-summary now (git pull)?"; then
        if git -C "$repo" pull --ff-only --quiet; then
            printf '  %s✓ Updated. Restart netbird-summary to run the new version.%s\n' "$GREEN" "$RESET"
        else
            printf '  %s✗ Update failed — you may have local changes. Run: git -C %s pull%s\n' "$RED" "$repo" "$RESET"
        fi
    fi
}

# ════════════════════════════════════════════════════════════════════════════════
#  Access policy (API-based)
# ════════════════════════════════════════════════════════════════════════════════

NB_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/netbird-summary"
NB_API_KEY_FILE="$NB_CONFIG_DIR/api_key"
NB_API_URL_FILE="$NB_CONFIG_DIR/api_url"

# Load stored API key into $NB_API_KEY. Returns 0 if found and non-empty.
_load_api_key() {
    [[ -f "$NB_API_KEY_FILE" ]] || return 1
    NB_API_KEY=$(cat "$NB_API_KEY_FILE")
    [[ -n "$NB_API_KEY" ]]
}

# Prompt for an API key, save it to disk (mode 600), set $NB_API_KEY.
_prompt_api_key() {
    printf '\n  %sNetBird API key not found.%s\n' "$YELLOW" "$RESET"
    printf '  Generate one in the dashboard under Settings → API Keys.\n'
    printf '  Paste your API key: '
    read -r NB_API_KEY
    if [[ -z "$NB_API_KEY" ]]; then
        printf '  %sNo key entered — aborting.%s\n' "$RED" "$RESET"
        return 1
    fi
    mkdir -p "$NB_CONFIG_DIR"
    chmod 700 "$NB_CONFIG_DIR"
    printf '%s' "$NB_API_KEY" > "$NB_API_KEY_FILE"
    chmod 600 "$NB_API_KEY_FILE"
    printf '  %s✓ Key saved to %s%s\n' "$GREEN" "$NB_API_KEY_FILE" "$RESET"
}

# Ensure $NB_API_KEY is set. Returns 0 if ready.
_require_api_key() { _load_api_key || _prompt_api_key; }

# Derive or load the management API base URL into $NB_API_BASE.
_require_api_url() {
    if [[ -f "$NB_API_URL_FILE" ]]; then
        NB_API_BASE=$(cat "$NB_API_URL_FILE")
        [[ -n "$NB_API_BASE" ]] && return 0
    fi
    # Extract HTTPS URL from the Management line of status output
    local url
    url=$(printf '%s' "$g_raw" | awk '/^Management:/' | grep -oE 'https?://[^[:space:]]+' | head -1)
    if [[ -n "$url" ]]; then
        NB_API_BASE="${url%/}/api"
        mkdir -p "$NB_CONFIG_DIR"
        chmod 700 "$NB_CONFIG_DIR"
        printf '%s' "$NB_API_BASE" > "$NB_API_URL_FILE"
        chmod 600 "$NB_API_URL_FILE"
        return 0
    fi
    printf '\n  %sCould not detect the management server URL from status output.%s\n' "$YELLOW" "$RESET"
    printf '  Enter the API base URL (e.g. https://my-server.com/api):\n  > '
    read -r NB_API_BASE
    if [[ -z "$NB_API_BASE" ]]; then
        printf '  %sNo URL entered — aborting.%s\n' "$RED" "$RESET"
        return 1
    fi
    mkdir -p "$NB_CONFIG_DIR"
    chmod 700 "$NB_CONFIG_DIR"
    printf '%s' "$NB_API_BASE" > "$NB_API_URL_FILE"
    chmod 600 "$NB_API_URL_FILE"
}

# Authenticated GET to the NetBird management API.
_nb_api() { curl -fsSL --max-time 15 \
    -H "Authorization: Token $NB_API_KEY" \
    -H "Accept: application/json" \
    "${NB_API_BASE}${1}"; }

show_access_policy() {
    _require_api_key || return 1

    # Status must be parsed before we can detect the management URL and this peer's IP.
    [[ -z "$g_raw" ]] && { parse_peers || return 1; }

    _require_api_url || return 1

    local my_ip
    my_ip=$(awk '/^NetBird IP:/{print $3}' <<< "$g_raw")
    if [[ -z "$my_ip" ]]; then
        printf '  %sCould not determine this peer'\''s NetBird IP from status output.%s\n' "$RED" "$RESET"
        return 1
    fi

    printf '\n  %s%sNetBird Access Policy%s\n' "$BOLD" "$CYAN" "$RESET"
    printf '  This peer: %s\n' "$my_ip"
    printf '  API:       %s\n\n' "$NB_API_BASE"
    printf '  %sFetching peers, groups, policies and network resources…%s\n' "$DIM" "$RESET"

    if ! command -v python3 >/dev/null 2>&1; then
        printf '  %spython3 is required for policy analysis but was not found.%s\n' "$RED" "$RESET"
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d 2>/dev/null) || { printf '  %sCould not create temp directory.%s\n' "$RED" "$RESET"; return 1; }

    local ok=0
    _nb_api "/peers"              > "$tmpdir/peers.json"     2>/dev/null && \
    _nb_api "/groups"             > "$tmpdir/groups.json"    2>/dev/null && \
    _nb_api "/policies"           > "$tmpdir/policies.json"  2>/dev/null && \
    _nb_api "/networks/resources" > "$tmpdir/res_list.json"  2>/dev/null && ok=1

    if (( ok == 0 )); then
        printf '  %sAPI call failed — verify your key and server URL.%s\n' "$RED" "$RESET"
        printf '  %sTo reset stored credentials delete: %s%s\n' "$DIM" "$NB_CONFIG_DIR" "$RESET"
        rm -rf "$tmpdir"
        return 1
    fi

    # Convert resource list → id→object map for O(1) lookup
    python3 -c "
import json
with open('$tmpdir/res_list.json') as f:
    lst = json.load(f)
if not isinstance(lst, list): lst = []
with open('$tmpdir/resources.json', 'w') as f:
    json.dump({r['id']: r for r in lst}, f)
" 2>/dev/null || printf '{}' > "$tmpdir/resources.json"

    # Real terminal width. `tput cols` inside $(...) sees a pipe on stdout and
    # falls back to the static terminfo default (80), so ask the tty directly.
    local cols
    cols=$( stty size </dev/tty 2>/dev/null | awk '{print $2}' )
    [[ "$cols" =~ ^[0-9]+$ && "$cols" -gt 0 ]] || cols=$( tput cols 2>/dev/null )
    [[ "$cols" =~ ^[0-9]+$ && "$cols" -gt 0 ]] || cols="${COLUMNS:-80}"
    [[ "$cols" =~ ^[0-9]+$ && "$cols" -gt 0 ]] || cols=80

    NB_COLS="$cols" python3 - "$my_ip" "$tmpdir" <<'PYEOF'
import json, sys, os

BOLD   = '\033[1m'
GREEN  = '\033[32m'
YELLOW = '\033[33m'
RED    = '\033[31m'
CYAN   = '\033[36m'
DIM    = '\033[2m'
RESET  = '\033[0m'

my_ip, tmpdir = sys.argv[1], sys.argv[2]

try:
    termw = int(os.environ.get('NB_COLS', '80'))
except ValueError:
    termw = 80
termw = max(60, termw)

def jload(path):
    with open(path) as f:
        data = json.load(f)
    return data if isinstance(data, list) else []

peers    = jload(os.path.join(tmpdir, 'peers.json'))
groups   = jload(os.path.join(tmpdir, 'groups.json'))
policies = jload(os.path.join(tmpdir, 'policies.json'))

with open(os.path.join(tmpdir, 'resources.json')) as f:
    resource_by_id = json.load(f)   # id → {name, address, type}

peer_by_id  = {p['id']: p for p in peers}
group_by_id = {g['id']: g for g in groups}

# Find this peer by its overlay IP (status appends /prefix, API does not)
my_ip_bare = my_ip.split('/')[0]
my_peer_id = next((p['id'] for p in peers if p.get('ip') == my_ip_bare), None)
if not my_peer_id:
    print(f"  {RED}This peer ({my_ip_bare}) was not found in the API peer list.{RESET}")
    print(f"  {DIM}Check that the API key has access to all peers.{RESET}")
    sys.exit(1)
my_peer_name = peer_by_id.get(my_peer_id, {}).get('name', my_ip_bare)

# Groups this peer belongs to
my_group_ids = {g['id'] for g in groups for p in (g.get('peers') or []) if p['id'] == my_peer_id}
my_group_names = sorted(group_by_id[gid]['name'] for gid in my_group_ids if gid in group_by_id)
print(f"  {BOLD}Member of groups:{RESET} {', '.join(my_group_names) or '(none)'}")

# Each entry: (policy_name, rule, dest_kind, dest_data, note)
#   dest_kind 'groups'   → dest_data is a set of group IDs
#   dest_kind 'peer'     → dest_data is a peer dict
#   dest_kind 'resource' → dest_data is a resource dict {name, address, type}
entries = []
for pol in policies:
    if not pol.get('enabled', True):
        continue
    for rule in (pol.get('rules') or []):
        if not rule.get('enabled', True):
            continue
        raw_src = rule.get('sources')       # list or null
        raw_dst = rule.get('destinations')  # list or null
        dst_res = rule.get('destinationResource')
        bidir   = rule.get('bidirectional', False)

        # Skip resource-to-resource rules (sources is null)
        if raw_src is None:
            continue

        src_ids = {g['id'] for g in raw_src}
        dst_ids = {g['id'] for g in (raw_dst or [])}
        is_src  = bool(src_ids & my_group_ids)
        is_dst  = bool(dst_ids & my_group_ids)

        if is_src:
            if raw_dst is not None:
                # Standard group→group rule
                entries.append((pol['name'], rule, 'groups', dst_ids, ''))
            elif dst_res:
                res_type = dst_res.get('type', '')
                res_id   = dst_res.get('id', '')
                if res_type == 'peer':
                    peer = peer_by_id.get(res_id)
                    if peer:
                        entries.append((pol['name'], rule, 'peer', peer, ''))
                else:
                    res = resource_by_id.get(res_id, {'name': res_id, 'address': '?', 'type': res_type})
                    entries.append((pol['name'], rule, 'resource', res, ''))

        # Bidirectional: peer only in destinations → it can also initiate to the source groups
        if bidir and is_dst and not is_src and raw_dst is not None:
            entries.append((pol['name'], rule, 'groups', src_ids, '(bidirectional — peer is destination)'))

if not entries:
    print(f"\n  {YELLOW}No outbound access policies found for this peer.{RESET}")
    sys.exit(0)

# ── Build normalized render blocks (one per policy rule) ─────────────────────
def _dot(connected):
    if connected is True:  return (GREEN, '●')
    if connected is False: return (RED, '●')
    return (DIM, '●')

blocks = []   # {policy, proto, tokens, rows:[{dot:(color,ch)|None, name, addr, dim}]}
for pol_name, rule, dest_kind, dest_data, note in entries:
    proto  = (rule.get('protocol') or 'all').upper()
    ports  = rule.get('ports') or []
    prs    = rule.get('port_ranges') or []
    tokens = sorted(ports, key=lambda x: int(x) if x.isdigit() else 0)
    if prs:
        tokens += [f"{r['start']}-{r['end']}" for r in prs]
    if proto == 'ALL':
        tokens = []                              # all ports

    rows = []
    if dest_kind == 'groups':
        for gid in sorted(dest_data):
            g = group_by_id.get(gid)
            if not g:
                continue
            members = [p for p in (g.get('peers') or []) if p['id'] != my_peer_id]
            rows.append({'dot': None, 'name': f"{g['name']} ({len(members)})", 'addr': '', 'dim': True})
            for pp in members:
                d = peer_by_id.get(pp['id'], {})
                rows.append({'dot': _dot(d.get('connected')), 'name': pp.get('name', pp['id']),
                             'addr': d.get('ip', '?'), 'dim': False})
            if not members:
                rows.append({'dot': None, 'name': '(no other peers)', 'addr': '', 'dim': True})
    elif dest_kind == 'peer':
        p = dest_data
        rows.append({'dot': _dot(p.get('connected')), 'name': p.get('name', '?'),
                     'addr': p.get('ip', '?'), 'dim': False})
    elif dest_kind == 'resource':
        r = dest_data
        rows.append({'dot': (CYAN, '◆'), 'name': r.get('name', '?'),
                     'addr': r.get('address', '?'), 'dim': False})

    pol_label = pol_name + (f" {note}" if note else '')
    blocks.append({'policy': pol_label, 'proto': proto, 'tokens': tokens, 'rows': rows})

# ── Size columns to the terminal: ports keep one line when wide and are the first ──
# ── to wrap as it narrows (floored at ~4 ports/line) before names truncate.        ──
GAPW, GAP        = 2, '  '
POLICY_CAP, POLICY_MIN = 30, 10
DEST_CAP,   DEST_MIN   = 26, 10
PORTS_MIN              = 26                       # room for ~4 five-digit ports

policy_w = min(POLICY_CAP, max([len('POLICY')]      + [len(b['policy']) for b in blocks]))
dest_w   = min(DEST_CAP,   max([len('DESTINATION')] + [len(r['name']) for b in blocks for r in b['rows']] or [0]))
addr_w   = min(18,         max([len('ADDRESS')]     + [len(r['addr']) for b in blocks for r in b['rows']] or [0]))
proto_w  = min(11,         max([len('PROTO')]       + [len(b['proto']) for b in blocks]))

overhead = 2 + GAPW * 4 + 2                       # indent + 4 gaps + dot+space
ports_w  = termw - overhead - policy_w - dest_w - addr_w - proto_w

# Phase 1: ports wrap first — reclaim from the name columns until ports reach their
# comfortable floor (≈4 ports/line) or the names hit their minimums.
need = PORTS_MIN - ports_w
if need > 0:
    take = min(need, policy_w - POLICY_MIN); policy_w -= take; ports_w += take; need -= take
if need > 0:
    take = min(need, dest_w - DEST_MIN);     dest_w   -= take; ports_w += take; need -= take

# Phase 2 (very narrow only): if columns still don't fit, shrink PROTO then ADDRESS
# so no line ever exceeds the terminal width.
HARD_MIN = 8
if ports_w < HARD_MIN:
    take = min(HARD_MIN - ports_w, proto_w - 3);  proto_w -= take; ports_w += take
if ports_w < HARD_MIN:
    take = min(HARD_MIN - ports_w, addr_w - 15);  addr_w  -= take; ports_w += take
ports_w = max(1, ports_w)

# Don't stretch wider than the longest single-line port list (keeps the table
# compact on very wide terminals; everything still fits on one line).
max_ports_line = max([3] + [len(', '.join(b['tokens'])) for b in blocks if b['tokens']])
ports_w = max(1, min(ports_w, max_ports_line))

def fit(s, w):
    if w <= 0:
        return ''
    if len(s) > w:
        s = s[:max(1, w - 1)] + '…'
    return s + ' ' * (w - len(s))

def wrap_ports(tokens, w):
    if not tokens:
        return ['all']
    lines, cur = [], ''
    for t in tokens:
        piece = t if not cur else ', ' + t
        if cur and len(cur) + len(piece) > w:
            lines.append(cur); cur = t
        else:
            cur += piece
    if cur:
        lines.append(cur)
    return lines

rule_w = min(termw - 2, 2 + policy_w + GAPW + 2 + dest_w + GAPW + addr_w + GAPW + proto_w + GAPW + ports_w)
RULE   = '─' * rule_w

print(f"\n  {BOLD}{CYAN}Outbound access — what {my_peer_name} can reach{RESET}")
print(f"  {BOLD}{fit('POLICY', policy_w)}{GAP}  {fit('DESTINATION', dest_w)}{GAP}"
      f"{fit('ADDRESS', addr_w)}{GAP}{fit('PROTO', proto_w)}{GAP}PORTS{RESET}")
print(f"  {BOLD}{RULE}{RESET}")

for bi, b in enumerate(blocks):
    plines = wrap_ports(b['tokens'], ports_w)
    rows   = b['rows']
    height = max(len(rows), len(plines))
    for i in range(height):
        if i == 0:
            pol = f"{BOLD}{fit(b['policy'], policy_w)}{RESET}"
            pro = fit(b['proto'], proto_w)
        else:
            pol = ' ' * policy_w
            pro = ' ' * proto_w
        if i < len(rows):
            r = rows[i]
            if r['dot'] is None:
                dot = '  '
            else:
                c, ch = r['dot']; dot = f"{c}{ch}{RESET} "
            nm = fit(r['name'], dest_w)
            if r['dim']:
                nm = f"{DIM}{nm}{RESET}"
            ad = fit(r['addr'], addr_w)
        else:
            dot, nm, ad = '  ', ' ' * dest_w, ' ' * addr_w
        pc = plines[i] if i < len(plines) else ''
        print(f"  {pol}{GAP}{dot}{nm}{GAP}{ad}{GAP}{pro}{GAP}{pc}")
    if bi != len(blocks) - 1:
        print()

print(f"  {BOLD}{RULE}{RESET}")
print(f"  {GREEN}●{RESET} {DIM}online peer{RESET}   {RED}●{RESET} {DIM}offline peer{RESET}   "
      f"{CYAN}◆{RESET} {DIM}host/subnet{RESET}")
PYEOF

    local rc=$?
    rm -rf "$tmpdir"
    return $rc
}

# ════════════════════════════════════════════════════════════════════════════════
#  Menu & dispatch
# ════════════════════════════════════════════════════════════════════════════════
show_help() {
    printf 'netbird-summary — NetBird peer summary and update checker\n\n'
    printf 'Usage:\n'
    printf '  netbird-summary              Show the summary, then an action prompt\n'
    printf '                               (just the summary when piped / non-interactive)\n'
    printf '  netbird-summary -s, --summary    Connected peers + stats only\n'
    printf '  netbird-summary -a, --all        ...also list idle / connecting peers\n'
    printf '  netbird-summary -p, --proxy      ...also list reverse-proxy peers\n'
    printf '  netbird-summary -A, --access     Show access policy (what this peer can reach)\n'
    printf '  netbird-summary -u, --update     Check for updates and offer to upgrade\n'
    printf '  netbird-summary -h, --help       Show this help\n\n'
    printf 'Access policy requires a NetBird API key (stored in %s).\n' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/netbird-summary/api_key"
    printf 'To reset stored API credentials, delete: %s\n\n' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/netbird-summary"
    printf 'On interactive launch it also checks GitHub (at most once/day) for newer\n'
    printf 'commits of this script and offers to git pull. Disable with NETBIRD_SUMMARY_NO_SELFCHECK=1.\n'
}

# Show the summary once, then loop a single-keypress action prompt.
run_interactive() {
    self_update_check
    show_summary
    local choice
    while true; do
        printf '\n  %sActions:%s  %s1%s client update   %s2%s idle peers   %s3%s proxy peers   %s4%s access policy   %ss%s summary   %su%s script update   %sq%s quit  ' \
            "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET"
        read -rsn1 choice
        printf '%s\n' "$choice"

        case "$choice" in
            1)         check_update ;;
            2)         parse_peers && render_idle ;;
            3)         parse_peers && render_proxy ;;
            4)         show_access_policy ;;
            s|S)       show_summary ;;
            u|U)       self_update_check force ;;
            q|Q|$'\e')  printf '\n'; return 0 ;;
            *)         printf '  %sInvalid option.%s\n' "$RED" "$RESET" ;;
        esac
    done
}

case "${1:-}" in
    -h|--help|help)        show_help ;;
    -u|--update|update)    check_update ;;
    -a|--all)              show_summary && render_idle ;;
    -p|--proxy|proxy)      show_summary && render_proxy ;;
    -s|--summary|summary)  show_summary ;;
    -A|--access|access)    parse_peers && show_access_policy ;;
    "")
        # Interactive terminal → summary + action prompt; piped → summary only (back-compat)
        if [[ -t 0 && -t 1 ]]; then
            run_interactive
        else
            show_summary
        fi
        ;;
    *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        show_help >&2
        exit 1
        ;;
esac
