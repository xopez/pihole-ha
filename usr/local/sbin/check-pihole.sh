#!/bin/bash

# ------------------------------------------------------------
# 1. Interface muss UP sein
# ------------------------------------------------------------

INTERFACE="$(ip route | awk '/default/ {print $5; exit}')"

if [ -z "$INTERFACE" ]; then
    exit 1
fi

if ! ip link show "$INTERFACE" | grep -q "state UP"; then
    exit 1
fi


# ------------------------------------------------------------
# 2. Pi-hole FTL muss laufen
# ------------------------------------------------------------

if ! systemctl is-active --quiet pihole-FTL; then
    exit 1
fi


# ------------------------------------------------------------
# 3. IPv4 DNS muss funktionieren
# ------------------------------------------------------------

if ! /usr/bin/dig \
    +time=2 \
    +tries=1 \
    @127.0.0.1 \
    -p 5335 \
    example.com \
    A >/dev/null 2>&1
then
    exit 1
fi


# ------------------------------------------------------------
# 4. IPv6 DNS muss funktionieren
# ------------------------------------------------------------

if ! /usr/bin/dig \
    +time=2 \
    +tries=1 \
    @::1 \
    -p 5335 \
    example.com \
    AAAA >/dev/null 2>&1
then
    exit 1
fi


# ------------------------------------------------------------
# Alles OK
# ------------------------------------------------------------

exit 0
