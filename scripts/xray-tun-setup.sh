#!/bin/bash
# Start xray TUN, wait for device, wire routing, wait for xray.
# Loop-proof: xray's own connection escapes via real gateway BEFORE default hijack.
# v6 included: default v6 also into TUN, with escapes for DNS servers + proxy server.

CFG=/home/mahdi/.config/v2ray-manager/config-xray-tun.json
STATE=/run/omarchy-v2ray-tun-routes.txt

cleanup() {
    # Restore direct routing on exit — but only if we actually hijacked.
    if [ -f "$STATE" ]; then
        ip route del 0.0.0.0/0 dev omarchy-tun metric 1 2>/dev/null
        ip -6 route del ::/0 dev omarchy-tun metric 1 2>/dev/null
        while read -r line; do
            # lines: "4 <ip>" or "6 <ip>" — escape routes we added
            fam=${line%% *}; dst=${line#* }
            if [ "$fam" = "4" ]; then
                ip route del "$dst" 2>/dev/null
            else
                ip -6 route del "$dst" 2>/dev/null
            fi
        done < "$STATE"
        rm -f "$STATE"
    fi
}
trap cleanup EXIT INT TERM

# 1) Resolve proxy server IPs BEFORE any routing changes
SERVER_IPS=$(python3 - "$CFG" <<'PYEOF'
import json, socket, sys
cfg = json.load(open(sys.argv[1]))
ips = set()
for ob in cfg.get("outbounds", []):
    for v in ob.get("settings", {}).get("vnext", []) or ob.get("settings", {}).get("servers", []) or []:
        host = v.get("address", "")
        try:
            for res in socket.getaddrinfo(host, None):
                ip = res[4][0]
                if "%" not in ip:
                    ips.add(ip)
        except Exception:
            pass
print("\n".join(sorted(ips)))
PYEOF
)

# 2) Real gateway + DNS servers, BEFORE hijacking
WAN_IF=""; WAN_GW=""
for i in $(seq 1 30); do
    WAN_IF=$(ip route show default | grep -v omarchy-tun | awk '{print $5; exit}')
    WAN_GW=$(ip route show default | grep -v omarchy-tun | awk '{print $3; exit}')
    [ -n "$WAN_IF" ] && [ -n "$WAN_GW" ] && break
    sleep 0.5
done
if [ -z "$WAN_IF" ] || [ -z "$WAN_GW" ]; then
    echo "no real gateway found; aborting" >&2
    exit 1
fi
# IPv6 link-local gateway + v6 DNS server addresses (DNS MUST stay direct)
WAN_GW6=$(ip -6 route show default | awk '{print $3; exit}')
DNS_IPS=$(resolvectl dns "$WAN_IF" 2>/dev/null | awk -F': ' '{print $2}' | tr ' ' '\n' | grep -E '^[0-9a-fA-F.:]+$' || true)

# 3) Start xray TUN
/usr/bin/xray run -c "$CFG" &
XPID=$!

# Wait for TUN device (max 10 s)
for i in $(seq 1 20); do
    if ip link show omarchy-tun >/dev/null 2>&1; then break; fi
    sleep 0.5
done
if ! ip link show omarchy-tun >/dev/null 2>&1; then
    echo "omarchy-tun did not appear; aborting" >&2
    kill "$XPID" 2>/dev/null
    exit 1
fi

# 4) Addresses on the TUN
ip addr add 172.19.0.1/30 dev omarchy-tun 2>/dev/null
ip addr add fdfe:dcba:9876::1/126 dev omarchy-tun 2>/dev/null

# 5) Escape routes FIRST (recorded for cleanup):
#    - proxy server IPs (loop prevention)
#    - DNS servers (resolved stub must reach uplink direct)
: > "$STATE"
add_escape() {
    local ip="$1"
    case "$ip" in
        *:*)
            ip -6 route replace "$ip/128" via "$WAN_GW6" dev "$WAN_IF" metric 1 2>/dev/null
            echo "6 $ip/128" >> "$STATE"
            ;;
        *)
            ip route replace "$ip/32" via "$WAN_GW" dev "$WAN_IF" metric 1 2>/dev/null
            echo "4 $ip/32" >> "$STATE"
            ;;
    esac
}
for ip in $SERVER_IPS; do add_escape "$ip"; done
for ip in $DNS_IPS; do add_escape "$ip"; done

# 6) Default v4 AND v6 into TUN (metric 1 beats dhcp metric 600)
ip route add 0.0.0.0/0 dev omarchy-tun metric 1 2>/dev/null
ip -6 route add ::/0 dev omarchy-tun metric 1 2>/dev/null

# 7) Wait for xray to exit
wait $XPID
