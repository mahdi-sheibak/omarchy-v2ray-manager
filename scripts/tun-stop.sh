#!/usr/bin/env bash
set -uo pipefail
TABLE=200
XRAY_UID=$(id -u mahdi 2>/dev/null || id -u)

iptables -t mangle -D PREROUTING -m owner --uid-owner "$XRAY_UID" -j MARK --set-mark 0x162 2>/dev/null || true
ip rule del fwmark 0x162 table main priority 10 2>/dev/null || true
ip route del default table "$TABLE" 2>/dev/null || true
ip route flush table "$TABLE" 2>/dev/null || true

echo "tun-stop: routing cleaned up"
