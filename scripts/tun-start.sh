#!/usr/bin/env bash
set -euo pipefail
IFACE="$1"
IP_ADDR="${2:-172.19.0.1/30}"
GW_IP="172.19.0.2"
GW_NET="172.19.0.0/30"
EXCLUDE_IP="${3:-}"
IFACE_MTU="${4:-9000}"
TABLE=200

ip link set "$IFACE" up mtu "$IFACE_MTU" 2>/dev/null || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP_ADDR" dev "$IFACE" 2>/dev/null || true
ip route add "$GW_NET" dev "$IFACE" proto kernel scope link src "${IP_ADDR%%/*}" 2>/dev/null || true

# Policy routing table: mark 0x162 (xray default UID) → bypass TUN, go direct
ip route add default via "$GW_IP" dev "$IFACE" table "$TABLE" 2>/dev/null || true
ip rule del fwmark 0x162 2>/dev/null || true
ip rule add fwmark 0x162 table main priority 10 2>/dev/null || true

# Default route through TUN (low priority so the bypass rule wins)
ip route add default via "$GW_IP" dev "$IFACE" metric 100 2>/dev/null || true

# Exclude VPN server IP if provided
if [ -n "$EXCLUDE_IP" ]; then
    ip route add "$EXCLUDE_IP" via "$(ip route show table main | grep "^default" | awk '{print $3}')" dev "$(ip route show table main | grep "^default" | awk '{print $5}')" metric 50 2>/dev/null || true
fi

# Mark xray/sing-box outbound connections to prevent routing loop
XRAY_UID=$(id -u mahdi 2>/dev/null || id -u)
iptables -t mangle -A PREROUTING -m owner --uid-owner "$XRAY_UID" -j MARK --set-mark 0x162 2>/dev/null || true

echo "tun-setup: $IFACE up with IP $IP_ADDR, table $TABLE, bypass mark 0x162"
