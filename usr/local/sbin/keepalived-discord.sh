#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN"

STATE="$1"

HOST="$(/bin/hostname)"
INSTANCE="PIHOLE"

INTERFACE="$(
    /sbin/ip -o route show default |
    /usr/bin/awk 'NR==1 {print $5}'
)"

if [[ -z "$INTERFACE" ]]; then
    INTERFACE="unknown"
fi

PRIORITY="$(
    /usr/bin/awk -v instance="$INSTANCE" '
        $1 == "vrrp_instance" && $2 == instance { found=1 }
        found && $1 == "priority" {
            print $2
            exit
        }
    ' /etc/keepalived/keepalived.conf
)"

IPV4="$(
    /sbin/ip -4 -o addr show dev "$INTERFACE" |
    /usr/bin/awk '$3 == "inet" && $4 !~ /^127\./ {print $4}' |
    /usr/bin/head -n1
)"

IPV6="$(
    /sbin/ip -6 -o addr show dev "$INTERFACE" |
    /usr/bin/awk '$3 == "inet6" && $4 !~ /^fe80:/ {print $4}' |
    /usr/bin/head -n1
)"

VIPV4="10.5.5.2/24"
VIPV6="fd00:5::2/64"

TIMESTAMP="$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"

case "$STATE" in
    MASTER)
        TITLE="🟢 Keepalived — MASTER"
        TEXT="**${HOST}** is now the active Pi-hole node."
        COLOR=5763719
        STATUS="🟢 MASTER"
        ;;
    BACKUP)
        TITLE="🟡 Keepalived — BACKUP"
        TEXT="**${HOST}** is now the standby Pi-hole node."
        COLOR=16776960
        STATUS="🟡 BACKUP"
        ;;
    *)
        exit 0
        ;;
esac

/usr/bin/curl -sS -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"embeds\": [{
            \"title\": \"${TITLE}\",
            \"description\": \"${TEXT}\",
            \"color\": ${COLOR},
            \"fields\": [
                {
                    \"name\": \"📊 STATUS\",
                    \"value\": \"\`\`\`text\nState       : ${STATUS}\nHost        : ${HOST}\nInterface   : ${INTERFACE}\nVRRP        : ${INSTANCE}\nPriority    : ${PRIORITY:-unknown}\n\`\`\`\",
                    \"inline\": false
                },
                {
                    \"name\": \"🌐 NETWORK\",
                    \"value\": \"\`\`\`text\nIPv4        : ${IPV4:-unknown}\nIPv6        : ${IPV6:-unknown}\n\`\`\`\",
                    \"inline\": false
                },
                {
                    \"name\": \"🔗 VIRTUAL IPs\",
                    \"value\": \"\`\`\`text\nIPv4        : ${VIPV4}\nIPv6        : ${VIPV6}\n\`\`\`\",
                    \"inline\": false
                }
            ],
            \"footer\": {
                \"text\": \"Pi-hole HA • Keepalived\"
            },
            \"timestamp\": \"${TIMESTAMP}\"
        }]
    }"
