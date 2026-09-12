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
# Read VRRP instance
# ============================================================

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

if [[ -z "$VRRP_CONFIG" ]]; then
    exit 0
fi


# ============================================================
# Priority
# ============================================================

PRIORITY="$(
    printf '%s\n' "$VRRP_CONFIG" |
    /usr/bin/awk '
        $1 == "priority" {
            print $2
            exit
        }
    '
)"

PRIORITY="${PRIORITY:-unknown}"


# ============================================================
# Virtual IPs
# ============================================================

VIPV4="$(
    printf '%s\n' "$VRRP_CONFIG" |
    /usr/bin/awk '
        $1 == "virtual_ipaddress" {
            in_vip = 1
            next
        }

        in_vip && $1 == "}" {
            exit
        }

        in_vip && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
            print $1
        }
    '
)"

VIPV6="$(
    printf '%s\n' "$VRRP_CONFIG" |
    /usr/bin/awk '
        $1 == "virtual_ipaddress" {
            in_vip = 1
            next
        }

        in_vip && $1 == "}" {
            exit
        }

        in_vip && $1 ~ /:/ {
            print $1
        }
    '
)"


# ============================================================
# Local IPv4 addresses
#
# Excludes:
#   - 127.0.0.0/8
#   - all configured VRRP IPv4 addresses
# ============================================================

IPV4="$(
    /sbin/ip -4 -o addr show dev "$INTERFACE" |
    /usr/bin/awk '
        $3 == "inet" && $4 !~ /^127\./ {
            print $4
        }
    ' |
    while read -r IP; do
        if ! printf '%s\n' "$VIPV4" | /usr/bin/grep -Fxq "$IP"; then
            printf '%s\n' "$IP"
        fi
    done
)"


# ============================================================
# Local IPv6 addresses
#
# Excludes:
#   - fe80::/10
#   - all configured VRRP IPv6 addresses
# ============================================================

IPV6="$(
    /sbin/ip -6 -o addr show dev "$INTERFACE" |
    /usr/bin/awk '
        $3 == "inet6" && $4 !~ /^fe80:/ {
            print $4
        }
    ' |
    while read -r IP; do
        if ! printf '%s\n' "$VIPV6" | /usr/bin/grep -Fxq "$IP"; then
            printf '%s\n' "$IP"
        fi
    done
)"


# ============================================================
# Defaults
# ============================================================

IPV4="${IPV4:-unknown}"
IPV6="${IPV6:-unknown}"
VIPV4="${VIPV4:-none}"
VIPV6="${VIPV6:-none}"


# ============================================================
# State
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
# Format lists for Discord
# ============================================================

IPV4_DISPLAY="$(
    printf '%s\n' "$IPV4" |
    /usr/bin/sed 's/^/            /'
)"

IPV6_DISPLAY="$(
    printf '%s\n' "$IPV6" |
    /usr/bin/sed 's/^/            /'
)"

VIPV4_DISPLAY="$(
    printf '%s\n' "$VIPV4" |
    /usr/bin/sed 's/^/            /'
)"

VIPV6_DISPLAY="$(
    printf '%s\n' "$VIPV6" |
    /usr/bin/sed 's/^/            /'
)"


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
        \"embeds\": [{
            \"title\": \"${TITLE}\",
            \"description\": \"${DESCRIPTION}\",
            \"color\": ${COLOR},

            \"fields\": [
                {
                    \"name\": \"📊 STATUS\",
                    \"value\": \"\`\`\`text\nState       : ${STATUS}\nHost        : ${HOST}\nInterface   : ${INTERFACE}\nVRRP        : ${INSTANCE}\nPriority    : ${PRIORITY}\n\`\`\`\",
                    \"inline\": false
                },
                {
                    \"name\": \"🌐 IP ADDRESSES\",
                    \"value\": \"\`\`\`text\nIPv4\n${IPV4_DISPLAY}\n\nIPv6\n${IPV6_DISPLAY}\n\`\`\`\",
                    \"inline\": false
                },
                {
                    \"name\": \"🔗 VIRTUAL IPs\",
                    \"value\": \"\`\`\`text\nIPv4\n${VIPV4_DISPLAY}\n\nIPv6\n${VIPV6_DISPLAY}\n\`\`\`\",
                    \"inline\": false
                }
            ],

            \"footer\": {
                \"text\": \"Pi-hole HA • Keepalived\"
            },

            \"timestamp\": \"${TIMESTAMP}\"
        }]
    }"
