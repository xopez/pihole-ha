#!/bin/bash

# ============================================================
# Configuration
# ============================================================

WEBHOOK_URL=""
KEEPALIVED_CONF="/etc/keepalived/keepalived.conf"
INSTANCE="PIHOLE"


# ============================================================
# Basic information
# ============================================================

STATE="$1"
HOST="$(/bin/hostname)"

INTERFACE="$(
    /sbin/ip -o route show default |
    /usr/bin/awk 'NR == 1 { print $5 }'
)"

[[ -z "$INTERFACE" ]] && INTERFACE="unknown"


# ============================================================
# Keepalived configuration
# ============================================================

# Extract the complete vrrp_instance block
VRRP_CONFIG="$(
    /usr/bin/awk -v instance="$INSTANCE" '
        $1 == "vrrp_instance" && $2 == instance {
            found = 1
        }

        found {
            print
        }

        found && /^}/ {
            exit
        }
    ' "$KEEPALIVED_CONF"
)"


# ============================================================
# Priority
# ============================================================

PRIORITY="$(
    printf '%s\n' "$VRRP_CONFIG" |
    /usr/bin/awk '$1 == "priority" { print $2; exit }'
)"

PRIORITY="${PRIORITY:-unknown}"


# ============================================================
# Virtual IPs
# ============================================================

# IPv4 VIPs
VIPV4="$(
    printf '%s\n' "$VRRP_CONFIG" |
    /usr/bin/awk '
        $1 == "virtual_ipaddress" {
            in_vip = 1
            next
        }

        in_vip && /^}/ {
            exit
        }

        in_vip && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
            print $1
        }
    '
)"

# IPv6 VIPs
VIPV6="$(
    printf '%s\n' "$VRRP_CONFIG" |
    /usr/bin/awk '
        $1 == "virtual_ipaddress" {
            in_vip = 1
            next
        }

        in_vip && /^}/ {
            exit
        }

        in_vip && $1 ~ /:/ {
            print $1
        }
    '
)"


# ============================================================
# Local IP addresses
#
# Excluded:
#   - IPv4 loopback
#   - IPv6 link-local
#   - all configured VRRP VIPs
# ============================================================

IPV4="$(
    /sbin/ip -4 -o addr show dev "$INTERFACE" |
    /usr/bin/awk '$3 == "inet" && $4 !~ /^127\./ { print $4 }' |
    while read -r IP; do

        if ! printf '%s\n' "$VIPV4" | grep -Fxq "$IP"; then
            echo "$IP"
        fi

    done
)"

IPV6="$(
    /sbin/ip -6 -o addr show dev "$INTERFACE" |
    /usr/bin/awk '$3 == "inet6" && $4 !~ /^fe80:/ { print $4 }' |
    while read -r IP; do

        if ! printf '%s\n' "$VIPV6" | grep -Fxq "$IP"; then
            echo "$IP"
        fi

    done
)"


# ============================================================
# Format IP addresses
# ============================================================

if [[ -n "$IPV4" ]]; then
    IPV4="$(
        printf '%s\n' "$IPV4" |
        /usr/bin/sed 's/^/            /'
    )"
else
    IPV4="            unknown"
fi

if [[ -n "$IPV6" ]]; then
    IPV6="$(
        printf '%s\n' "$IPV6" |
        /usr/bin/sed 's/^/            /'
    )"
else
    IPV6="            unknown"
fi


# ============================================================
# Format Virtual IPs
# ============================================================

if [[ -n "$VIPV4" ]]; then
    VIPV4="$(
        printf '%s\n' "$VIPV4" |
        /usr/bin/sed 's/^/            /'
    )"
else
    VIPV4="            none"
fi

if [[ -n "$VIPV6" ]]; then
    VIPV6="$(
        printf '%s\n' "$VIPV6" |
        /usr/bin/sed 's/^/            /'
    )"
else
    VIPV6="            none"
fi


# ============================================================
# Keepalived state
# ============================================================

case "$STATE" in

    MASTER)
        TITLE="🟢 Keepalived — MASTER"
        STATUS="🟢 MASTER"
        DESCRIPTION="**${HOST}** is now the active Pi-hole node."
        COLOR=5763719
        ;;

    BACKUP)
        TITLE="🟡 Keepalived — BACKUP"
        STATUS="🟡 BACKUP"
        DESCRIPTION="**${HOST}** is now the standby Pi-hole node."
        COLOR=16776960
        ;;

    *)
        exit 0
        ;;

esac


# ============================================================
# Timestamp
# ============================================================

TIMESTAMP="$(
    /bin/date -u +"%Y-%m-%dT%H:%M:%SZ"
)"


# ============================================================
# Discord Webhook
# ============================================================

/usr/bin/curl -sS -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"embeds\": [
            {
                \"title\": \"${TITLE}\",
                \"description\": \"${DESCRIPTION}\",
                \"color\": ${COLOR},

                \"fields\": [

                    {
                        \"name\": \"📊 STATUS\",
                        \"value\": \"\`\`\`text
State       : ${STATUS}
Host        : ${HOST}
Interface   : ${INTERFACE}
VRRP        : ${INSTANCE}
Priority    : ${PRIORITY}
\`\`\`\",
                        \"inline\": false
                    },

                    {
                        \"name\": \"🌐 IP ADDRESSES\",
                        \"value\": \"\`\`\`text
IPv4
${IPV4}

IPv6
${IPV6}
\`\`\`\",
                        \"inline\": false
                    },

                    {
                        \"name\": \"🔗 VIRTUAL IPs\",
                        \"value\": \"\`\`\`text
IPv4
${VIPV4}

IPv6
${VIPV6}
\`\`\`\",
                        \"inline\": false
                    }

                ],

                \"footer\": {
                    \"text\": \"Pi-hole HA • Keepalived\"
                },

                \"timestamp\": \"${TIMESTAMP}\"
            }
        ]
    }"
