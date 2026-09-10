#!/bin/bash

# ------------------------------------------------------------
# 1. Active network interface must be UP
# ------------------------------------------------------------

INTERFACE="$(ip route show default | awk 'NR == 1 {print $5}')"

if [[ -z "$INTERFACE" ]] || ! ip link show "$INTERFACE" | grep -q "state UP"; then
    exit 1
fi


# ------------------------------------------------------------
# 2. Pi-hole FTL must be running
# ------------------------------------------------------------

if ! systemctl is-active --quiet pihole-FTL; then
    exit 1
fi


# ------------------------------------------------------------
# 3. IPv4 DNS must be working
# ------------------------------------------------------------

if ! /usr/bin/dig \
    +time=2 \
    +tries=1 \
    @127.0.0.1 \
    -p 53 \
    dns-test.moserlab.de \
    A \
    >/dev/null 2>&1
then
    exit 1
fi


# ------------------------------------------------------------
# 4. IPv6 DNS must be working
# ------------------------------------------------------------

if ! /usr/bin/dig \
    +time=2 \
    +tries=1 \
    @::1 \
    -p 53 \
    dns-test.moserlab.de \
    AAAA \
    >/dev/null 2>&1
then
    exit 1
fi


# ------------------------------------------------------------
# All checks passed
# ------------------------------------------------------------

exit 0
