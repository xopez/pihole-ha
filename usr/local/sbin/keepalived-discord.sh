#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN"

STATE="$1"

HOST="$(hostname)"
INSTANCE="PIHOLE"

INTERFACE="$(ip route show default | awk 'NR==1 {print $5}')"

if [[ -z "$INTERFACE" ]]; then
    INTERFACE="unknown"
fi

PRIORITY="$(
    awk -v instance="$INSTANCE" '
        $1 == "vrrp_instance" && $2 == instance { found=1 }
        found && $1 == "priority" {
            print $2
            exit
        }
    ' /etc/keepalived/keepalived.conf
)"

IPV4="$(
    ip -4 addr show dev "$INTERFACE" scope global |
    awk '/inet / {print $2}' |
    head -n1
)"

IPV6="$(
    ip -6 addr show dev "$INTERFACE" scope global |
    awk '/inet6 / && $2 !~ /^fe80:/ {print $2}' |
    head -n1
)"

VIPV4="10.5.5.2/24"
VIPV6="fd00:5::2/64"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

case "$STATE" in
    MASTER)
        TITLE="🟢 Keepalived: MASTER"
        TEXT="${HOST} is now MASTER"
        COLOR=3066993
        ;;
    BACKUP)
        TITLE="🟡 Keepalived: BACKUP"
        TEXT="${HOST} is now BACKUP"
        COLOR=16776960
        ;;
    *)
        exit 0
        ;;
esac

curl -sS -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"embeds\": [{
            \"title\": \"${TITLE}\",
            \"description\": \"${TEXT}\",
            \"color\": ${COLOR},
            \"fields\": [
                {
                    \"name\": \"Host\",
                    \"value\": \"\`${HOST}\`\",
                    \"inline\": true
                },
                {
                    \"name\": \"Interface\",
                    \"value\": \"\`${INTERFACE}\`\",
                    \"inline\": true
                },
                {
                    \"name\": \"VRRP Instance\",
                    \"value\": \"\`${INSTANCE}\`\",
                    \"inline\": true
                },
                {
                    \"name\": \"Priority\",
                    \"value\": \"\`${PRIORITY:-unknown}\`\",
                    \"inline\": true
                },
                {
                    \"name\": \"IPv4 VIP\",
                    \"value\": \"\`${VIPV4}\`\",
                    \"inline\": true
                },
                {
                    \"name\": \"IPv6 VIP\",
                    \"value\": \"\`${VIPV6}\`\",
                    \"inline\": true
                },
                {
                    \"name\": \"IPv4 Address\",
                    \"value\": \"\`${IPV4:-unknown}\`\",
                    \"inline\": true
                },
                {
                    \"name\": \"IPv6 Address\",
                    \"value\": \"\`${IPV6:-unknown}\`\",
                    \"inline\": true
                }
            ],
            \"footer\": {
                \"text\": \"Keepalived / Pi-hole HA\"
            },
            \"timestamp\": \"${TIMESTAMP}\"
        }]
    }"
