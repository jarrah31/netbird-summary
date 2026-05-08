#!/usr/bin/env bash
# netbird-summary — concise peer connection summary
# Compatible with bash 3.2+ (macOS default)

BOLD=$'\033[1m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
CYAN=$'\033[36m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# Truncate a string to max chars, appending … if trimmed
trunc() {
    local s="$1" max="$2"
    (( ${#s} > max )) && printf '%s' "${s:0:$((max-1))}…" || printf '%s' "$s"
}

# ── Fetch status output ────────────────────────────────────────────────────────
if ! raw=$(netbird status --detail 2>&1); then
    printf 'Error running netbird status --detail:\n%s\n' "$raw" >&2
    exit 1
fi

# ── Column widths ──────────────────────────────────────────────────────────────
cN=36; cI=18; cS=12; cT=9; cC=14; cH=24; cL=12

# ── Row buffer (indexed array — bash 3.2 safe) ─────────────────────────────────
rows=()

# ── Current peer state ─────────────────────────────────────────────────────────
p_name=""
p_ip="—"; p_status="—"; p_type="—"
p_ice="—"; p_shake="—"; p_latency="—"

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

# ── Parse line by line ─────────────────────────────────────────────────────────
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

# ── Build separator ────────────────────────────────────────────────────────────
total=$(( cN + cI + cS + cT + cC + cH + cL + 10 ))
SEP=$(printf '─%.0s' $(seq 1 "$total"))

# ── Print header ───────────────────────────────────────────────────────────────
printf '\n  %s%sNetBird Peer Connection Summary%s\n' "$BOLD" "$CYAN" "$RESET"
printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"
printf '  %s  %-'"${cN}"'s %-'"${cI}"'s %-'"${cS}"'s %-'"${cT}"'s %-'"${cC}"'s %-'"${cH}"'s %s%s\n' \
    "$BOLD" \
    "PEER" "NETBIRD IP" "STATUS" "TYPE" "ICE (L/R)" "LAST HANDSHAKE" "LATENCY" \
    "$RESET"
printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"

# ── Print rows ─────────────────────────────────────────────────────────────────
if (( ${#rows[@]} == 0 )); then
    printf '  %s  No peers found.%s\n' "$DIM" "$RESET"
else
    for row in "${rows[@]}"; do
        printf '%s\n' "$row"
    done
fi

printf '  %s%s%s\n' "$BOLD" "$SEP" "$RESET"

# ── Legend & ICE reference ─────────────────────────────────────────────────────
printf '\n  %sLegend:%s  %s● P2P (direct)%s   %s● Relayed%s   %s● Disconnected/Connecting%s\n' \
    "$DIM" "$RESET" "$GREEN" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"

printf '\n  %sICE candidate types (Local/Remote):%s\n' "$BOLD" "$RESET"
printf '  %s  host%s   — direct LAN address; both sides on same network or no NAT\n'  "$GREEN"  "$RESET"
printf '  %s  srflx%s  — server-reflexive; public IP discovered via STUN (most common, still P2P)\n' "$GREEN" "$RESET"
printf '  %s  prflx%s  — peer-reflexive; address discovered mid-handshake (peer-to-peer, slightly indirect)\n' "$CYAN" "$RESET"
printf '  %s  relay%s  — TURN relay in use; traffic is not peer-to-peer\n'             "$YELLOW" "$RESET"
printf '  %s  -%s      — not yet negotiated (connecting or relayed with no ICE path)\n' "$RED"    "$RESET"

# ── System info ────────────────────────────────────────────────────────────────
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
