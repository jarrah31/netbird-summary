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
show_summary() {
    local raw
    if ! raw=$(netbird status --detail 2>&1); then
        printf 'Error running netbird status --detail:\n%s\n' "$raw" >&2
        return 1
    fi

    # ── Column widths ───────────────────────────────────────────────────────────
    local cN=36 cI=18 cS=12 cT=9 cC=14 cH=24 cL=12

    # ── Row buffer (indexed array — bash 3.2 safe) ──────────────────────────────
    local rows=()

    # ── Current peer state ──────────────────────────────────────────────────────
    local p_name="" p_ip="—" p_status="—" p_type="—"
    local p_ice="—" p_shake="—" p_latency="—"

    flush_peer() {
        [[ -z "$p_name" ]] && return

        local st="$p_status" ty="$p_type" ind

        if   [[ "$st" == Connected && "$ty" == P2P     ]]; then ind="${GREEN}●${RESET}"
        elif [[ "$st" == Connected && "$ty" == Relayed  ]]; then ind="${YELLOW}●${RESET}"
        elif [[ "$st" == Connected                       ]]; then ind="${CYAN}●${RESET}"
        else                                                       ind="${RED}●${RESET}"
        fi

        rows+=("$(printf '  %s %-'"${cN}"'s %-'"${cI}"'s %-'"${cS}"'s %-'"${cT}"'s %-'"${cC}"'s %-'"${cH}"'s %s' \
            "$ind" \
            "$(trunc "$p_name"    $cN)" \
            "$(trunc "$p_ip"      $cI)" \
            "$(trunc "$st"        $cS)" \
            "$(trunc "$ty"        $cT)" \
            "$(trunc "$p_ice"     $cC)" \
            "$(trunc "$p_shake"   $cH)" \
            "$(trunc "$p_latency" $cL)")")
    }

    reset_peer() {
        p_name=""
        p_ip="—"; p_status="—"; p_type="—"
        p_ice="—"; p_shake="—"; p_latency="—"
    }

    # ── Parse line by line ──────────────────────────────────────────────────────
    local line
    while IFS= read -r line; do
        # Peer header: one leading space, name (not starting with - or :), ends with colon
        if [[ "$line" =~ ^[[:space:]]([^[:space:]:-][^:]*):$ ]]; then
            flush_peer
            reset_peer
            p_name="${BASH_REMATCH[1]}"

        elif [[ -z "$p_name" ]]; then
            continue

        elif [[ "$line" =~ ^[[:space:]]+NetBird\ IP:\ (.+)$ ]]; then
            p_ip="${BASH_REMATCH[1]}"

        elif [[ "$line" =~ ^[[:space:]]+Status:\ (.+)$ ]]; then
            p_status="${BASH_REMATCH[1]}"

        elif [[ "$line" =~ ^[[:space:]]+Connection\ type:\ (.+)$ ]]; then
            p_type="${BASH_REMATCH[1]}"

        elif [[ "$line" =~ ^[[:space:]]+ICE\ candidate\ \(Local/Remote\):\ (.+)$ ]]; then
            p_ice="${BASH_REMATCH[1]}"

        elif [[ "$line" =~ ^[[:space:]]+Last\ [Ww]ire[Gg]uard\ handshake:\ (.+)$ ]]; then
            p_shake="${BASH_REMATCH[1]}"

        elif [[ "$line" =~ ^[[:space:]]+Latency:\ (.+)$ ]]; then
            p_latency="${BASH_REMATCH[1]}"

        elif [[ "$line" =~ ^(Events:|OS:) ]]; then
            flush_peer
            reset_peer
        fi

    done <<< "$raw"
    flush_peer  # catch last peer if output ended without Events:/OS:

    # ── Build separator ─────────────────────────────────────────────────────────
    local total=$(( cN + cI + cS + cT + cC + cH + cL + 10 ))
    local SEP
    SEP=$(printf '─%.0s' $(seq 1 "$total"))

    # ── Print header ────────────────────────────────────────────────────────────
    printf '\n  %s%sNetBird Peer Connection Summary%s\n' "$BOLD" "$CYAN" "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
    printf '  %s  %-'"${cN}"'s %-'"${cI}"'s %-'"${cS}"'s %-'"${cT}"'s %-'"${cC}"'s %-'"${cH}"'s %s%s\n' \
        "$BOLD" \
        "PEER" "NETBIRD IP" "STATUS" "TYPE" "ICE (L/R)" "LAST HANDSHAKE" "LATENCY" \
        "$RESET"
    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"

    # ── Print rows ──────────────────────────────────────────────────────────────
    if (( ${#rows[@]} == 0 )); then
        printf '  %s  No peers found.%s\n' "$DIM" "$RESET"
    else
        local row
        for row in "${rows[@]}"; do
            printf '%s\n' "$row"
        done
    fi

    printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"

    # ── Legend & ICE reference ──────────────────────────────────────────────────
    printf '\n  %sLegend:%s  %s● P2P (direct)%s   %s● Relayed%s   %s● Disconnected/Connecting%s\n' \
        "$DIM" "$RESET" "$GREEN" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"

    printf '\n  %sICE candidate types (Local/Remote):%s\n' "$BOLD" "$RESET"
    printf '  %s  host%s   — direct LAN address; both sides on same network or no NAT\n'  "$GREEN"  "$RESET"
    printf '  %s  srflx%s  — server-reflexive; public IP discovered via STUN (most common, still P2P)\n' "$GREEN" "$RESET"
    printf '  %s  prflx%s  — peer-reflexive; address discovered mid-handshake (peer-to-peer, slightly indirect)\n' "$CYAN" "$RESET"
    printf '  %s  relay%s  — TURN relay in use; traffic is not peer-to-peer\n'             "$YELLOW" "$RESET"
    printf '  %s  -%s      — not yet negotiated (connecting or relayed with no ICE path)\n' "$RED"    "$RESET"

    # ── System info ─────────────────────────────────────────────────────────────
    local nb_ip peers_cnt profile daemon mgmt
    nb_ip=$(     awk '/^NetBird IP:/{print $3}'                    <<< "$raw")
    peers_cnt=$( awk '/^Peers count:/{print $3}'                   <<< "$raw")
    profile=$(   awk '/^Profile:/{print $2}'                       <<< "$raw")
    daemon=$(    awk '/^Daemon version:/{print $3}'                 <<< "$raw")
    mgmt=$(      awk '/^Management:/{$1=""; sub(/^ /,""); print}'  <<< "$raw")

    printf '\n'
    printf '  %s%-20s%s%s\n' "$BOLD" "This peer IP:"    "$RESET" "$nb_ip"
    printf '  %s%-20s%s%s\n' "$BOLD" "Peers connected:" "$RESET" "${peers_cnt:-unknown}"
    [[ -n "$profile" ]] &&
    printf '  %s%-20s%s%s\n' "$BOLD" "Profile:"         "$RESET" "$profile"
    printf '  %s%-20s%s%s\n' "$BOLD" "Management:"      "$RESET" "$mgmt"
    printf '  %s%-20s%s%s\n' "$BOLD" "Daemon version:"  "$RESET" "$daemon"
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

# Detect how netbird was installed → "apt", "dnf", "yum", or "script"
detect_install_method() {
    if command -v dpkg >/dev/null 2>&1 && dpkg -s netbird >/dev/null 2>&1; then
        echo apt
    elif command -v rpm >/dev/null 2>&1 && rpm -q netbird >/dev/null 2>&1; then
        if   command -v dnf >/dev/null 2>&1; then echo dnf
        elif command -v yum >/dev/null 2>&1; then echo yum
        else echo script
        fi
    else
        echo script   # binary install via the official install.sh
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
    printf '  netbird-summary             Interactive menu (or summary when piped)\n'
    printf '  netbird-summary -s, --summary   Show the peer connection summary\n'
    printf '  netbird-summary -u, --update    Check for updates and offer to upgrade\n'
    printf '  netbird-summary -h, --help      Show this help\n'
}

show_menu() {
    printf '\n  %s%sNetBird Summary%s\n' "$BOLD" "$CYAN" "$RESET"
    printf '  %s───────────────%s\n' "$BOLD" "$RESET"
    printf '    %s1%s  Peer connection summary\n' "$BOLD" "$RESET"
    printf '    %s2%s  Check for client updates\n' "$BOLD" "$RESET"
    printf '    %sq%s  Quit\n' "$BOLD" "$RESET"
    printf '\n  Select an option: '

    local choice
    read -rsn1 choice
    printf '%s\n' "$choice"

    case "$choice" in
        1)        show_summary ;;
        2)        check_update ;;
        q|Q|$'\e') printf '\n' ;;
        *)        printf '\n  %sInvalid option.%s\n' "$RED" "$RESET"; return 1 ;;
    esac
}

case "${1:-}" in
    -h|--help|help)        show_help ;;
    -u|--update|update)    check_update ;;
    -s|--summary|summary)  show_summary ;;
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
