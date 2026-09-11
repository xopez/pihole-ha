#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN"

NAME="$1"
STATE="$2"
HOST="$(hostname)"

case "$STATE" in
    MASTER)
        TEXT="${HOST} is now MASTER"
        COLOR=3066993
        ;;
    BACKUP)
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
            \"title\": \"Keepalived State Change\",
            \"description\": \"${TEXT}\",
            \"color\": ${COLOR},
            \"fields\": [
                {
                    \"name\": \"VRRP Instance\",
                    \"value\": \"${NAME}\",
                    \"inline\": true
                }
            ]
        }]
    }"
