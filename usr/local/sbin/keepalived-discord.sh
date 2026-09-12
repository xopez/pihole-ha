#!/bin/bash

set -u

WEBHOOK_URL=""
CONFIG="/etc/keepalived/keepalived.conf"
INSTANCE="PIHOLE"

STATE="${1:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
    exit 1
}

# Extract a property from the requested vrrp_instance block.
vrrp_value() {
    local key="$1"

    awk -v instance="$INSTANCE" -v key="$key" '
        $1 == "vrrp_instance" && $2 == instance {
            in_instance=1
            depth=0
        }

        in_instance {
            for (i = 1; i <= NF; i++) {
                if ($i == "{") depth++
                if ($i == "}") depth--
            }

            if ($1 == key && NF >= 2) {
                print $2
                exit
            }

            if (depth <= 0 && $0 ~ /}/)
                exit
        }
    ' "$CONFIG"
}

# Extract all addresses from a virtual_ipaddress* block belonging to
# the requested vrrp_instance.
vrrp_ips() {
    local block="$1"

    awk -v instance="$INSTANCE" -v target="$block" '
        $1 == "vrrp_instance" && $2 == instance {
            in_instance=1
            depth=0
        }

        in_instance {
            # Enter the requested block.
            if ($1 == target) {
                in_block=1
                block_depth=0
            }

            if (in_block) {
                for (i = 1; i <= NF; i++) {
                    if ($i == "{") block_depth++
                    if ($i == "}") block_depth--
                }

                # Ignore the "virtual_ipaddress {" line itself.
                if ($1 != target && $1 != "{") {
                    for (i = 1; i <= NF; i++) {
                        value=$i

                        # Ignore interface/option syntax.
                        if (value ~ /^[0-9a-fA-F:.]+\/[0-9]+$/)
                            print value
                    }
                }

                if (block_depth <= 0 && $0 ~ /}/) {
                    in_block=0
                }
            }

            for (i = 1; i <= NF; i++) {
                if ($i == "{") depth++
                if ($i == "}") depth--
            }

            if (depth <= 0 && $0 ~ /}/)
                exit
        }
    ' "$CONFIG"
}

# ---------------------------------------------------------------------------
# Validate state
# ---------------------------------------------------------------------------

case "$STATE" in
    MASTER)
        TITLE="🟢 Keepalived — MASTER"
        TEXT="**${HOST:-unknown}** is now the active Pi-hole node."
        COLOR=5763719
        STATUS="🟢 MASTER"
        ;;

    BACKUP)
        TITLE="🟡 Keepalived — BACKUP"
        TEXT="**${HOST:-unknown}** is now the standby Pi-hole node."
        COLOR=16776960
        STATUS="🟡 BACKUP"
        ;;

    *)
        exit 0
        ;;
esac

[[ -n "$WEBHOOK_URL" ]] || die
[[ -r "$CONFIG" ]] || die

# ---------------------------------------------------------------------------
# Basic system information
# ---------------------------------------------------------------------------

HOST="$(hostname)"

INTERFACE="$(
    ip -o route show default |
        awk 'NR == 1 { print $5; exit }'
)"

INTERFACE="${INTERFACE:-unknown}"

# ---------------------------------------------------------------------------
# Keepalived / VRRP configuration
# ---------------------------------------------------------------------------

VRRP_INTERFACE="$(vrrp_value interface)"
PRIORITY="$(vrrp_value priority)"
VRRP_STATE="$(vrrp_value state)"

VRRP_INTERFACE="${VRRP_INTERFACE:-$INTERFACE}"
PRIORITY="${PRIORITY:-unknown}"
VRRP_STATE="${VRRP_STATE:-unknown}"

# Prefer the interface explicitly configured for this VRRP instance.
# Fall back to the default route interface.
if [[ "$VRRP_INTERFACE" != "unknown" ]]; then
    INTERFACE="$VRRP_INTERFACE"
fi

# ---------------------------------------------------------------------------
# Local IP addresses
# ---------------------------------------------------------------------------

# All IPv4 addresses except loopback.
IPV4="$(
    ip -4 -o addr show dev "$INTERFACE" |
        awk '$3 == "inet" && $4 !~ /^127\./ { print $4 }' |
        paste -sd ', ' -
)"

# All IPv6 addresses except link-local.
IPV6="$(
    ip -6 -o addr show dev "$INTERFACE" |
        awk '$3 == "inet6" && $4 !~ /^fe80:/ { print $4 }' |
        paste -sd ', ' -
)"

IPV4="${IPV4:-unknown}"
IPV6="${IPV6:-unknown}"

# ---------------------------------------------------------------------------
# Virtual IP addresses from keepalived.conf
# ---------------------------------------------------------------------------

# Normal VRRP virtual addresses.
VIPV4="$(
    vrrp_ips "virtual_ipaddress" |
        awk -F/ '$1 !~ /:/ { print }' |
        paste -sd ', ' -
)"

VIPV6="$(
    vrrp_ips "virtual_ipaddress" |
        awk -F/ '$1 ~ /:/ { print }' |
        paste -sd ', ' -
)"

# Also include addresses from virtual_ipaddress_excluded if present.
VIPV4_EXCLUDED="$(
    vrrp_ips "virtual_ipaddress_excluded" |
        awk -F/ '$1 !~ /:/ { print }' |
        paste -sd ', ' -
)"

VIPV6_EXCLUDED="$(
    vrrp_ips "virtual_ipaddress_excluded" |
        awk -F/ '$1 ~ /:/ { print }' |
        paste -sd ', ' -
)"

[[ -n "$VIPV4_EXCLUDED" ]] && \
    VIPV4="${VIPV4:+$VIPV4, }$VIPV4_EXCLUDED"

[[ -n "$VIPV6_EXCLUDED" ]] && \
    VIPV6="${VIPV6:+$VIPV6, }$VIPV6_EXCLUDED"

VIPV4="${VIPV4:-none}"
VIPV6="${VIPV6:-none}"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ---------------------------------------------------------------------------
# Build Discord payload with jq
# ---------------------------------------------------------------------------

jq -n \
    --arg title "$TITLE" \
    --arg description "$TEXT" \
    --arg status "$STATUS" \
    --arg host "$HOST" \
    --arg interface "$INTERFACE" \
    --arg instance "$INSTANCE" \
    --arg priority "$PRIORITY" \
    --arg configured_state "$VRRP_STATE" \
    --arg ipv4 "$IPV4" \
    --arg ipv6 "$IPV6" \
    --arg vipv4 "$VIPV4" \
    --arg vipv6 "$VIPV6" \
    --arg timestamp "$TIMESTAMP" \
    --argjson color "$COLOR" \
    '{
        embeds: [{
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
                        "VRRP        : " + $instance + "\n" +
                        "Priority    : " + $priority + "\n" +
                        "Config State: " + $configured_state + "\n" +
                        "```"
                    ),
                    inline: false
                },
                {
                    name: "🌐 NETWORK",
                    value: (
                        "```text\n" +
                        "IPv4        : " + $ipv4 + "\n" +
                        "IPv6        : " + $ipv6 + "\n" +
                        "```"
                    ),
                    inline: false
                },
                {
                    name: "🔗 VIRTUAL IPs",
                    value: (
                        "```text\n" +
                        "IPv4        : " + $vipv4 + "\n" +
                        "IPv6        : " + $vipv6 + "\n" +
                        "```"
                    ),
                    inline: false
                }
            ],

            footer: {
                text: "Pi-hole HA • Keepalived"
            },

            timestamp: $timestamp
        }]
    }' |
    curl \
        --fail \
        --silent \
        --show-error \
        --max-time 10 \
        -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        --data-binary @-
