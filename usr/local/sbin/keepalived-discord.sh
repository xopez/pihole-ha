#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN"

TYPE="$1"
NAME="$2"
STATE="$3"
HOST="$(hostname)"

case "$STATE" in
    MASTER)
        COLOR=3066993
        TEXT="ist jetzt MASTER"
        ;;
    BACKUP)
        COLOR=16776960
        TEXT="ist jetzt BACKUP"
        ;;
    FAULT)
        COLOR=15158332
        TEXT="ist in FAULT"
        ;;
    *)
        COLOR=9807270
        TEXT="hat den Zustand geändert: $STATE"
        ;;
esac

curl -sS -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"embeds\": [{
            \"title\": \"Keepalived Zustandsänderung\",
            \"description\": \"**${HOST}** ${TEXT}\",
            \"color\": ${COLOR},
            \"fields\": [
                {
                    \"name\": \"VRRP Instance\",
                    \"value\": \"${NAME}\",
                    \"inline\": true
                },
                {
                    \"name\": \"Typ\",
                    \"value\": \"${TYPE}\",
                    \"inline\": true
                }
            ]
        }]
    }"
