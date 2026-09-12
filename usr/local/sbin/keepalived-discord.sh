#!/bin/bash

set -u

# ============================================================================
# Configuration
# ============================================================================

WEBHOOK_URL=""
CONFIG="/etc/keepalived/keepalived.conf"

# ============================================================================
# Validate arguments
# ============================================================================

STATE="${1:-}"

case "$STATE" in
    MASTER)
        TITLE="🟢 Keepalived — MASTER"
        COLOR=5763719
        STATUS="🟢 MASTER"
        TEXT="is now the active Pi-hole node."
        ;;

    BACKUP)
        TITLE="🟡 Keepalived — BACKUP"
        COLOR=16776960
        STATUS="🟡 BACKUP"
        TEXT="is now the standby Pi-hole node."
        ;;

    *)
        exit 0
        ;;
esac

[[ -n "$WEBHOOK_URL" ]] || exit 1
[[ -r "$CONFIG" ]] || exit 1
[[ -x "$(command -v jq)" ]] || exit 1
[[ -x "$(command -v curl)" ]] || exit 1

# ============================================================================
# Basic system information
# ============================================================================

HOST="$(hostname)"

# Interface from the default route.
DEFAULT_INTERFACE="$(
    ip -o route show default 2>/dev/null |
        awk 'NR == 1 { print $5; exit }'
)"

DEFAULT_INTERFACE="${DEFAULT_INTERFACE:-unknown}"

# ============================================================================
# Parse all VRRP instances
#
# Output format:
#
# INSTANCE|STATE|INTERFACE|VRID|PRIORITY|VIP4|VIP6
#
# Example:
#
# PIHOLE_V4|MASTER|eth0|51|150|10.5.5.2/24|
# PIHOLE_V6|MASTER|eth0|52|150||fd00:5::2/64
#
# ============================================================================

VRRP_DATA="$(
    awk '
        function trim(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            return s
        }

        # --------------------------------------------------------------------
        # New VRRP instance
        # --------------------------------------------------------------------

        /^[[:space:]]*vrrp_instance[[:space:]]+/ {
            if (instance != "")
                print instance "|" state "|" interface "|" vrid "|" priority "|" vip4 "|" vip6

            instance=$2
            gsub(/\{/, "", instance)

            state=""
            interface=""
            vrid=""
            priority=""
            vip4=""
            vip6=""

            in_instance=1
            instance_depth=0
            in_vip=0

            next
        }

        in_instance {

            # ----------------------------------------------------------------
            # Track braces
            # ----------------------------------------------------------------

            line=$0

            opens=gsub(/\{/, "{", line)
            closes=gsub(/\}/, "}", line)

            instance_depth += opens
            instance_depth -= closes

            # ----------------------------------------------------------------
            # Basic VRRP parameters
            # ----------------------------------------------------------------

            if ($1 == "state")
                state=$2

            if ($1 == "interface")
                interface=$2

            if ($1 == "virtual_router_id")
                vrid=$2

            if ($1 == "priority")
                priority=$2

            # ----------------------------------------------------------------
            # virtual_ipaddress block
            # ----------------------------------------------------------------

            if ($1 == "virtual_ipaddress" && $2 == "{") {
                in_vip=1
                next
            }

            if (in_vip && $1 == "}") {
                in_vip=0
                next
            }

            if (in_vip) {
                ip=$1
                sub(/[[:space:]].*$/, "", ip)

                # IPv4
                if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\//) {
                    if (vip4 == "")
                        vip4=ip
                    else
                        vip4=vip4 ", " ip
                }

                # IPv6
                else if (ip ~ /:/) {
                    if (vip6 == "")
                        vip6=ip
                    else
                        vip6=vip6 ", " ip
                }
            }

            # ----------------------------------------------------------------
            # End of VRRP instance
            # ----------------------------------------------------------------

            if (instance_depth <= 0 && $0 ~ /}/) {
                print instance "|" state "|" interface "|" vrid "|" priority "|" vip4 "|" vip6

                instance=""
                state=""
                interface=""
                vrid=""
                priority=""
                vip4=""
                vip6=""

                in_instance=0
                in_vip=0
            }
        }

        END {
            if (instance != "")
                print instance "|" state "|" interface "|" vrid "|" priority "|" vip4 "|" vip6
        }
    ' "$CONFIG"
)"

# Remove empty lines.
VRRP_DATA="$(
    printf '%s\n' "$VRRP_DATA" |
        sed '/^[[:space:]]*$/d'
)"

# ============================================================================
# Build lists of configured VRRP VIPs
#
# These lists are used for:
#   1. Excluding VRRP VIPs from NETWORK
#   2. Detecting which configured VIPs are actually active
# ============================================================================

CONFIGURED_VIPV4="$(
    printf '%s\n' "$VRRP_DATA" |
        awk -F'|' '
            {
                if ($6 != "") {
                    n = split($6, vips, ", ")

                    for (i = 1; i <= n; i++)
                        if (vips[i] != "")
                            print vips[i]
                }
            }
        '
)"

CONFIGURED_VIPV6="$(
    printf '%s\n' "$VRRP_DATA" |
        awk -F'|' '
            {
                if ($7 != "") {
                    n = split($7, vips, ", ")

                    for (i = 1; i <= n; i++)
                        if (vips[i] != "")
                            print vips[i]
                }
            }
        '
)"

# ============================================================================
# VRRP summary
# ============================================================================

VRRP_INSTANCES="$(
    printf '%s\n' "$VRRP_DATA" |
        cut -d'|' -f1 |
        paste -sd ', ' -
)"

VRRP_INSTANCES="${VRRP_INSTANCES:-unknown}"

# ============================================================================
# Build per-instance display
# ============================================================================

VRRP_STATUS=""

while IFS='|' read -r INSTANCE STATE_CONFIG VRRP_INTERFACE VRID PRIORITY VIP4 VIP6; do

    [[ -n "$INSTANCE" ]] || continue

    VRRP_STATUS+="${INSTANCE}"$'\n'
    VRRP_STATUS+="  State       : ${STATE_CONFIG:-unknown}"$'\n'
    VRRP_STATUS+="  Interface   : ${VRRP_INTERFACE:-unknown}"$'\n'
    VRRP_STATUS+="  VRID        : ${VRID:-unknown}"$'\n'
    VRRP_STATUS+="  Priority    : ${PRIORITY:-unknown}"$'\n'
    VRRP_STATUS+="  IPv4 VIP    : ${VIP4:-none}"$'\n'
    VRRP_STATUS+="  IPv6 VIP    : ${VIP6:-none}"$'\n'
    VRRP_STATUS+=$'\n'

done <<< "$VRRP_DATA"

VRRP_STATUS="${VRRP_STATUS%$'\n'}"
VRRP_STATUS="${VRRP_STATUS:-unknown}"

# ============================================================================
# Local IPv4 addresses
#
# Show only real/local interface addresses.
# All configured VRRP IPv4 VIPs are excluded dynamically.
# ============================================================================

IPV4="$(
    ip -4 -o addr show scope global 2>/dev/null |
        awk -v vips="$CONFIGURED_VIPV4" '
            BEGIN {
                n = split(vips, list, "\n")

                for (i = 1; i <= n; i++) {
                    vip = list[i]

                    if (vip != "") {
                        # Remove CIDR prefix.
                        sub(/\/.*/, "", vip)
                        vrrp_vip[vip] = 1
                    }
                }
            }

            {
                interface = $2
                address = $4

                # Remove CIDR prefix for comparison.
                ip = address
                sub(/\/.*/, "", ip)

                # Skip VRRP VIP.
                if (ip in vrrp_vip)
                    next

                printf "%s: %s\n", interface, address
            }
        ' |
        paste -sd '\n' -
)"

IPV4="${IPV4:-none}"

# ============================================================================
# Local IPv6 addresses
#
# Show only real/local interface addresses.
# All configured VRRP IPv6 VIPs are excluded dynamically.
# ============================================================================

IPV6="$(
    ip -6 -o addr show scope global 2>/dev/null |
        awk -v vips="$CONFIGURED_VIPV6" '
            BEGIN {
                n = split(vips, list, "\n")

                for (i = 1; i <= n; i++) {
                    vip = list[i]

                    if (vip != "") {
                        # Remove CIDR prefix.
                        sub(/\/.*/, "", vip)
                        vrrp_vip[vip] = 1
                    }
                }
            }

            {
                interface = $2
                address = $4

                # Remove CIDR prefix for comparison.
                ip = address
                sub(/\/.*/, "", ip)

                # Skip VRRP VIP.
                if (ip in vrrp_vip)
                    next

                printf "%s: %s\n", interface, address
            }
        ' |
        paste -sd '\n' -
)"

IPV6="${IPV6:-none}"

# ============================================================================
# Currently active VRRP IPv4 VIPs
#
# Compare the configured VIPs against the addresses currently assigned
# to the system. Only VIPs that are actually present are displayed.
# ============================================================================

ACTIVE_VIPV4="$(
    ip -4 -o addr show scope global 2>/dev/null |
        awk -v vips="$CONFIGURED_VIPV4" '
            BEGIN {
                n = split(vips, list, "\n")

                for (i = 1; i <= n; i++) {
                    vip = list[i]

                    if (vip != "") {
                        # Keep the complete CIDR representation.
                        configured[vip] = 1

                        # Also create a version without CIDR.
                        plain = vip
                        sub(/\/.*/, "", plain)
                        configured_plain[plain] = vip
                    }
                }
            }

            {
                address = $4

                # Remove CIDR prefix.
                ip = address
                sub(/\/.*/, "", ip)

                if (ip in configured_plain)
                    active[configured_plain[ip]] = 1
            }

            END {
                first = 1

                for (vip in active) {
                    if (!first)
                        printf ", "

                    printf "%s", vip
                    first = 0
                }

                if (!first)
                    printf "\n"
            }
        '
)"

ACTIVE_VIPV4="${ACTIVE_VIPV4:-none}"

# ============================================================================
# Currently active VRRP IPv6 VIPs
#
# Compare the configured VIPs against the addresses currently assigned
# to the system. Only VIPs that are actually present are displayed.
# ============================================================================

ACTIVE_VIPV6="$(
    ip -6 -o addr show scope global 2>/dev/null |
        awk -v vips="$CONFIGURED_VIPV6" '
            BEGIN {
                n = split(vips, list, "\n")

                for (i = 1; i <= n; i++) {
                    vip = list[i]

                    if (vip != "") {
                        configured[vip] = 1

                        # Also create a version without CIDR.
                        plain = vip
                        sub(/\/.*/, "", plain)
                        configured_plain[plain] = vip
                    }
                }
            }

            {
                address = $4

                # Remove CIDR prefix.
                ip = address
                sub(/\/.*/, "", ip)

                if (ip in configured_plain)
                    active[configured_plain[ip]] = 1
            }

            END {
                first = 1

                for (vip in active) {
                    if (!first)
                        printf ", "

                    printf "%s", vip
                    first = 0
                }

                if (!first)
                    printf "\n"
            }
        '
)"

ACTIVE_VIPV6="${ACTIVE_VIPV6:-none}"

# ============================================================================
# Timestamp
# ============================================================================

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ============================================================================
# Discord payload
# ============================================================================

jq -n \
    --arg title "$TITLE" \
    --arg description "**${HOST}** ${TEXT}" \
    --arg status "$STATUS" \
    --arg host "$HOST" \
    --arg interface "$DEFAULT_INTERFACE" \
    --arg instances "$VRRP_INSTANCES" \
    --arg vrrp_status "$VRRP_STATUS" \
    --arg ipv4 "$IPV4" \
    --arg ipv6 "$IPV6" \
    --arg active_vipv4 "$ACTIVE_VIPV4" \
    --arg active_vipv6 "$ACTIVE_VIPV6" \
    --arg timestamp "$TIMESTAMP" \
    --argjson color "$COLOR" \
    '{
        embeds: [
            {
                title: $title,
                description: $description,
                color: $color,

                fields: [
                    {
                        name: "📊 STATUS",
                        value: (
                            "```text\n" +
                            "State       : " + $status + "\n" +
                            "Host        : " + $host + "\n" +
                            "Interface   : " + $interface + "\n" +
                            "VRRP        : " + $instances + "\n" +
                            "```"
                        ),
                        inline: false
                    },

                    {
                        name: "🔄 VRRP INSTANCES",
                        value: (
                            "```text\n" +
                            $vrrp_status +
                            "\n```"
                        ),
                        inline: false
                    },

                    {
                        name: "🌐 NETWORK",
                        value: (
                            "```text\n" +
                            "IPv4:\n" +
                            $ipv4 +
                            "\n\nIPv6:\n" +
                            $ipv6 +
                            "\n```"
                        ),
                        inline: false
                    },

                    {
                        name: "🔗 ACTIVE VIRTUAL IPs",
                        value: (
                            "```text\n" +
                            "IPv4        : " + $active_vipv4 + "\n" +
                            "IPv6        : " + $active_vipv6 + "\n" +
                            "```"
                        ),
                        inline: false
                    }
                ],

                footer: {
                    text: "Pi-hole HA • Keepalived"
                },

                timestamp: $timestamp
            }
        ]
    }' |
    curl \
        --fail \
        --silent \
        --show-error \
        --max-time 10 \
        -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        --data-binary @-
