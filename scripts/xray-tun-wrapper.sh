#!/bin/bash
# Root-owned TUN wrapper for omarchy-v2ray-manager (xray-core backend).
# Installed to /usr/local/lib/omarchy-v2ray/ (root:root 0755) by scripts/install.sh.
# Runs as the invoking user (User=%i, ambient CAP_NET_ADMIN) — NOT as root.
# The unit must never execute code from a user-writable path, so this wrapper
# validates the config path before handing off to the (also root-owned)
# routing script.
set -euo pipefail

CFG="$1"
[ -n "$CFG" ] || { echo "usage: xray-tun-wrapper <config>" >&2; exit 1; }
[ -f "$CFG" ] || { echo "config missing: $CFG" >&2; exit 1; }

CFG_REAL="$(readlink -f -- "$CFG")"
USER_NAME="$(id -un)"
USER_HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"

# Config must live under the service user's home and be owned by them.
case "$CFG_REAL" in
  "$USER_HOME"/*) ;;
  *) echo "config outside service-user home denied: $CFG_REAL" >&2; exit 1 ;;
esac
[ "$(stat -c '%U' "$CFG_REAL")" = "$USER_NAME" ] || { echo "config not owned by service user" >&2; exit 1; }

# Config must not be group/other-writable (prevents tampering by other local users).
MODE="$(stat -c '%a' "$CFG_REAL")"
[ $((8#$MODE & 8#022)) -eq 0 ] || { echo "config group/other-writable: $MODE" >&2; exit 1; }

# Config must parse as JSON and declare a TUN inbound.
# xray-core uses `protocol: tun`; sing-box uses `type: tun`.
python3 - "$CFG_REAL" <<'PYEOF' || { echo "config rejected by validator" >&2; exit 1; }
import json, sys
cfg = json.load(open(sys.argv[1]))
inbounds = cfg.get("inbounds", [])
if not any(i.get("type") == "tun" or i.get("protocol") == "tun" for i in inbounds):
    sys.exit(1)
PYEOF

exec /usr/local/lib/omarchy-v2ray/xray-tun-setup "$CFG_REAL"
