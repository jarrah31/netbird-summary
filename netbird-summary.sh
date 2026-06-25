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

show_summary() {
    local mode="${1:-}"   # "all" → also list idle / connecting peers
    local raw
    if ! raw=$(netbird status --detail 2>&1); then
        printf 'Error running netbird status --detail:\n%s\n' "$raw" >&2
        return 1
    fi

    # ── Per-peer parallel arrays (bash 3.2 safe) ────────────────────────────────
    local names=() ips=() statuses=() types=() ices=() ends=() txs=() shakes=() lats=() fors=()
    local p_name p_ip p_status p_type p_ice p_end p_tx p_shake p_lat p_for

    reset_peer() {
        p_name=""; p_ip="-"; p_status="-"; p_type="-"; p_ice="-"
        p_end="-"; p_tx="-"; p_shake="-"; p_lat="-"; p_for="-"
    }
    flush_peer() {
        [[ -z "$p_name" ]] && return
        names+=("$p_name");   ips+=("$p_ip");       statuses+=("$p_status")
        types+=("$p_type");   ices+=("$p_ice");     ends+=("$p_end")
        txs+=("$p_tx");       shakes+=("$p_shake"); lats+=("$p_lat"); fors+=("$p_for")
    }
    reset_peer

    # ── Parse line by line ──────────────────────────────────────────────────────
    local line
    while IFS= read -r line; do
        # Peer header: one leading space, name (not starting with - or :), ends with colon
        if [[ "$line" =~ ^[[:space:]]([^[:space:]:-][^:]*):$ ]]; then
            flush_peer; reset_peer; p_name="${BASH_REMATCH[1]}"

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
            flush_peer; reset_peer
        fi

    done <<< "$raw"
    flush_peer  # catch last peer if output ended without Events:/OS:

    # ── Tally ───────────────────────────────────────────────────────────────────
    local count=${#names[@]} connected=0 p2p=0 relayed=0 idle=0 i
    for ((i=0; i<count; i++)); do
        if [[ "${statuses[$i]}" == Connected ]]; then
            connected=$((connected+1))
            case "${types[$i]}" in
                P2P)     p2p=$((p2p+1)) ;;
                Relayed) relayed=$((relayed+1)) ;;
            esac
        else
            idle=$((idle+1))
        fi
    done

    # ── Connected peers table ───────────────────────────────────────────────────
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

    if (( connected == 0 )); then
        printf '  %s  No connected peers.%s\n' "$DIM" "$RESET"
    else
        local ind
        for ((i=0; i<count; i++)); do
            [[ "${statuses[$i]}" == Connected ]] || continue
            if   [[ "${types[$i]}" == P2P     ]]; then ind="${GREEN}●${RESET}"
            elif [[ "${types[$i]}" == Relayed ]]; then ind="${YELLOW}●${RESET}"
            else                                       ind="${CYAN}●${RESET}"
            fi
            printf "$rowfmt" "$ind" \
                "$(trunc "${names[$i]}"                   $cN)" \
                "$(trunc "${ips[$i]}"                     $cI)" \
                "$(trunc "${types[$i]}"                   $cT)" \
                "$(trunc "${ices[$i]}"                    $cE)" \
                "$(trunc "${ends[$i]}"                    $cP)" \
                "$(trunc "$(abbr_bytes "${txs[$i]}")"     $cX)" \
                "$(trunc "$(abbr_dur   "${shakes[$i]}")"  $cH)" \
                "$(trunc "$(abbr_lat   "${lats[$i]}")"    $cL)"
        done
    fi
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"

    # ── Idle / connecting peers ─────────────────────────────────────────────────
    if (( idle > 0 )); then
        if [[ "$mode" == all ]]; then
            local dN=46 dI=16 dS=12
            local dtot=$(( dN + dI + dS + 12 + 8 ))
            local DSEP; DSEP=$(printf '─%.0s' $(seq 1 "$dtot"))
            printf '\n  %s%sIdle / connecting peers%s  %s(%d)%s\n' "$BOLD" "$CYAN" "$RESET" "$DIM" "$idle" "$RESET"
            printf '  %s%s%s\n' "$BOLD" "$DSEP" "$RESET"
            printf '  %s  %-'"$dN"'s %-'"$dI"'s %-'"$dS"'s %s%s\n' \
                "$BOLD" "PEER" "NETBIRD IP" "STATUS" "FOR" "$RESET"
            printf '  %s%s%s\n' "$BOLD" "$DSEP" "$RESET"
            for ((i=0; i<count; i++)); do
                [[ "${statuses[$i]}" == Connected ]] && continue
                printf '  %s %-'"$dN"'s %-'"$dI"'s %-'"$dS"'s %s\n' \
                    "${RED}●${RESET}" \
                    "$(trunc "${names[$i]}"    $dN)" \
                    "$(trunc "${ips[$i]}"      $dI)" \
                    "$(trunc "${statuses[$i]}" $dS)" \
                    "$(abbr_dur "${fors[$i]}")"
            done
            printf '  %s%s%s\n' "$BOLD" "$DSEP" "$RESET"
            printf '  %sFOR = time since the connection state last changed. A large value means the\n' "$DIM"
            printf '  peer has been unreachable (offline), or it is an on-demand / lazy-connection peer.%s\n' "$RESET"
        else
            printf '\n  %s+ %d idle / connecting peer(s) hidden.%s  Show them: menu option %s3%s or %snetbird-summary --all%s\n' \
                "$DIM" "$idle" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET"
        fi
    fi

    # ── Legend & ICE reference ──────────────────────────────────────────────────
    printf '\n  %sLegend:%s  %s● P2P (direct)%s   %s● Relayed%s   %s● Idle/Connecting%s\n' \
        "$DIM" "$RESET" "$GREEN" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"

    printf '\n  %sICE candidate types (Local/Remote):%s\n' "$BOLD" "$RESET"
    printf '  %s  host%s   — direct LAN address; both sides on same network or no NAT\n'  "$GREEN"  "$RESET"
    printf '  %s  srflx%s  — server-reflexive; public IP discovered via STUN (most common, still P2P)\n' "$GREEN" "$RESET"
    printf '  %s  prflx%s  — peer-reflexive; address discovered mid-handshake (peer-to-peer, slightly indirect)\n' "$CYAN" "$RESET"
    printf '  %s  relay%s  — TURN relay in use; traffic is not peer-to-peer\n'             "$YELLOW" "$RESET"
    printf '  %s  -%s      — not yet negotiated (connecting or relayed with no ICE path)\n' "$RED"    "$RESET"

    # ── System info ─────────────────────────────────────────────────────────────
    local nb_ip profile daemon mgmt
    nb_ip=$(   awk '/^NetBird IP:/{print $3}'                   <<< "$raw")
    profile=$( awk '/^Profile:/{print $2}'                      <<< "$raw")
    daemon=$(  awk '/^Daemon version:/{print $3}'                <<< "$raw")
    mgmt=$(    awk '/^Management:/{$1=""; sub(/^ /,""); print}' <<< "$raw")

    printf '\n'
    printf '  %s%-16s%s%s\n' "$BOLD" "This peer IP:" "$RESET" "$nb_ip"
    printf '  %s%-16s%s%d total · %s%d connected%s (%d P2P, %d relayed) · %s%d idle/connecting%s\n' \
        "$BOLD" "Peers:" "$RESET" "$count" "$GREEN" "$connected" "$RESET" "$p2p" "$relayed" "$YELLOW" "$idle" "$RESET"
    [[ -n "$profile" ]] &&
    printf '  %s%-16s%s%s\n' "$BOLD" "Profile:"        "$RESET" "$profile"
    printf '  %s%-16s%s%s\n' "$BOLD" "Management:"     "$RESET" "$mgmt"
    printf '  %s%-16s%s%s\n' "$BOLD" "Daemon version:" "$RESET" "$daemon"
    printf '\n'
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
#  Menu & dispatch
# ════════════════════════════════════════════════════════════════════════════════
show_help() {
    printf 'netbird-summary — NetBird peer summary and update checker\n\n'
    printf 'Usage:\n'
    printf '  netbird-summary              Interactive menu (or summary when piped)\n'
    printf '  netbird-summary -s, --summary    Show connected peers\n'
    printf '  netbird-summary -a, --all        Show all peers, incl. idle / connecting\n'
    printf '  netbird-summary -u, --update     Check for updates and offer to upgrade\n'
    printf '  netbird-summary -h, --help       Show this help\n'
}

show_menu() {
    local choice
    while true; do
        printf '\n  %s%sNetBird Summary%s\n' "$BOLD" "$CYAN" "$RESET"
        printf '  %s───────────────%s\n' "$BOLD" "$RESET"
        printf '    %s1%s  Peer connection summary\n' "$BOLD" "$RESET"
        printf '    %s2%s  Check for client updates\n' "$BOLD" "$RESET"
        printf '    %s3%s  All peers (incl. idle / connecting)\n' "$BOLD" "$RESET"
        printf '    %sq%s  Quit\n' "$BOLD" "$RESET"
        printf '\n  Select an option: '

        read -rsn1 choice
        printf '%s\n' "$choice"

        case "$choice" in
            1)         show_summary ;;
            2)         check_update ;;
            3)         show_summary all ;;
            q|Q|$'\e')  printf '\n'; return 0 ;;
            *)         printf '\n  %sInvalid option.%s\n' "$RED" "$RESET" ;;
        esac
    done
}

case "${1:-}" in
    -h|--help|help)        show_help ;;
    -u|--update|update)    check_update ;;
    -a|--all)              show_summary all ;;
    -s|--summary|summary)  show_summary "${2:-}" ;;
    "")
        # Interactive terminal → menu; piped/non-interactive → summary (back-compat)
        if [[ -t 0 && -t 1 ]]; then
            show_menu
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
