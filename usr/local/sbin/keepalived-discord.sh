#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN"

STATE="$1"

HOST="$(hostname)"
INSTANCE="PIHOLE"

PRIORITY="$(grep -A20 "vrrp_instance ${INSTANCE}" /etc/keepalived/keepalived.conf \
    | grep -m1 "priority" \
    | awk '{print $2}')"

IPV4="$(ip -4 addr show dev eth0 scope global \
    | awk '/inet / {print $2}' \
    | head -n1)"

IPV6="$(ip -6 addr show dev eth0 scope global \
    | awk '/inet6 / && $2 !~ /^fe80:/ {print $2}' \
    | head -n1)"

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
                    \"name\": \"VRRP Instance\",
                    \"value\": \"\`${INSTANCE}\`\",
                    \"inline\": true
                },
                {
                    \"name\": \"Priority\",
                    \"value\": \"\`${PRIORITY}\`\",
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
