#!/bin/bash

# ============================================================
# Pi-hole / Unbound Health Check
#
# Exit 0 = healthy
# Exit 1 = unhealthy
# ============================================================

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
LOCAL_IPV4="127.0.0.1"
LOCAL_IPV6="::1"

PIHOLE_DNS_PORT="53"
UNBOUND_DNS_PORT="5335"

DNS_TEST_DOMAIN="dns-test.moserlab.de"

# ------------------------------------------------------------
# 1. Active network interface must be UP
# ------------------------------------------------------------
INTERFACE="$(ip route show default | awk 'NR == 1 {print $5}')"

if [[ -z "$INTERFACE" ]] || \
   ! ip link show "$INTERFACE" | grep -q "state UP"; then
    exit 1
fi

# ------------------------------------------------------------
# 2. Pi-hole FTL must be running
# ------------------------------------------------------------
if ! systemctl is-active --quiet pihole-FTL; then
    exit 1
fi

# ------------------------------------------------------------
# 3. Unbound must be running
# ------------------------------------------------------------
if ! systemctl is-active --quiet unbound; then
    exit 1
fi

# ------------------------------------------------------------
# 4. Unbound IPv4 DNS must be working
# ------------------------------------------------------------
if ! /usr/bin/dig \
    +time=1 \
    +tries=1 \
    @"${LOCAL_IPV4}" \
    -p "${UNBOUND_DNS_PORT}" \
    "${DNS_TEST_DOMAIN}" \
    A \
    >/dev/null 2>&1
then
    exit 1
fi

# ------------------------------------------------------------
# 5. Pi-hole IPv4 DNS must be working
# ------------------------------------------------------------
if ! /usr/bin/dig \
    +time=1 \
    +tries=1 \
    @"${LOCAL_IPV4}" \
    -p "${PIHOLE_DNS_PORT}" \
    "${DNS_TEST_DOMAIN}" \
    A \
    >/dev/null 2>&1
then
    exit 1
fi

# ------------------------------------------------------------
# 6. Pi-hole IPv6 DNS must be working
# ------------------------------------------------------------
if ! /usr/bin/dig \
    +time=1 \
    +tries=1 \
    @"${LOCAL_IPV6}" \
    -p "${PIHOLE_DNS_PORT}" \
    "${DNS_TEST_DOMAIN}" \
    AAAA \
    >/dev/null 2>&1
then
    exit 1
fi

# ============================================================
# All checks passed
# ============================================================

exit 0
