#!/usr/bin/env bash
# Install omarchy-v2ray-manager CLI + systemd units.
# Called by Service.qml on first status check if CLI missing; or manually.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
CLI_SRC="$PLUGIN_DIR/bin/omarchy-v2ray"
CLI_DST="$BIN_DIR/omarchy-v2ray"
CLI="$CLI_DST"

mkdir -p "$BIN_DIR"
chmod +x "$CLI_SRC" 2>/dev/null || true

# Prefer copying so plugin removal doesn't break the running CLI mid-flight;
# users who want the linked copy can replace it themselves.
cp -f "$CLI_SRC" "$CLI_DST"
chmod +x "$CLI_DST"

# First run creates ~/.config/v2ray-manager/ and initial state.
"$CLI_DST" status >/dev/null 2>&1 || true

# Helper scripts: user copy for reference/manual use.
CONF_DIR="$HOME/.config/v2ray-manager"
mkdir -p "$CONF_DIR"
for script in tun-start.sh tun-stop.sh xray-tun-setup; do
    cp -f "$PLUGIN_DIR/scripts/$script" "$CONF_DIR/$script"
    chmod +x "$CONF_DIR/$script"
done

# User-level units (proxy mode). Hardcode %h via $HOME — units use absolute paths.
for unit in omarchy-v2ray.service omarchy-v2ray-xray.service; do
    src="$PLUGIN_DIR/systemd/$unit"
    dst="$HOME/.config/systemd/user/$unit"
    if [ ! -f "$dst" ]; then
        mkdir -p "$HOME/.config/systemd/user"
        sed "s|/home/mahdi|$HOME|g" "$src" > "$dst"
    fi
done
systemctl --user daemon-reload

# System-level units (TUN mode) need root + polkit.
# Root-executed helpers go to a ROOT-OWNED path, never user-writable:
#   /usr/local/lib/omarchy-v2ray/{xray-tun-wrapper,xray-tun-setup,tun-start.sh,tun-stop.sh}
# and system units to /etc/systemd/system/. Verified ownership/mode after copy.
# BEST-EFFORT: if root install fails here (no TTY for pkexec/sudo when spawned
# from Quickshell), we continue — the CLI falls back to `pkexec systemctl start`
# at first TUN connect, which shows a GUI prompt at the right moment.
have_pkexec() { command -v pkexec >/dev/null 2>&1; }

ROOT_HELPER_DIR="/usr/local/lib/omarchy-v2ray"
SYS_UNITS="omarchy-v2ray-tun.service omarchy-v2ray-xray-tun.service"

units_needed=0
for unit in $SYS_UNITS; do
    [ -f "/etc/systemd/system/$unit" ] || units_needed=1
done
[ -f "$ROOT_HELPER_DIR/xray-tun-setup" ] || units_needed=1

if [ "$units_needed" = "1" ]; then
    echo "TUN units/helpers missing. Installing requires root (polkit prompt):"
    install_root_parts() {
        mkdir -p "$ROOT_HELPER_DIR"
        cp -f "$PLUGIN_DIR/scripts/xray-tun-wrapper.sh" "$ROOT_HELPER_DIR/xray-tun-wrapper"
        cp -f "$PLUGIN_DIR/scripts/xray-tun-setup" "$ROOT_HELPER_DIR/xray-tun-setup"
        cp -f "$PLUGIN_DIR/scripts/tun-start.sh" "$ROOT_HELPER_DIR/tun-start.sh"
        cp -f "$PLUGIN_DIR/scripts/tun-stop.sh" "$ROOT_HELPER_DIR/tun-stop.sh"
        chmod 0755 "$ROOT_HELPER_DIR"/*
        chown root:root "$ROOT_HELPER_DIR"/*
        for unit in $SYS_UNITS; do
            src="$PLUGIN_DIR/systemd/$unit"
            dst="/etc/systemd/system/$unit"
            sed "s|%i|$PLUGIN_USER|g" "$src" > "$dst"
        done
        systemctl daemon-reload
    }
    PLUGIN_USER="$(id -un)"
    export PLUGIN_USER
    if have_pkexec; then
        pkexec env PLUGIN_USER="$PLUGIN_USER" PLUGIN_DIR="$PLUGIN_DIR" bash -c "$(declare -f install_root_parts); install_root_parts" \
            || echo "warn: root helpers/units not installed (will prompt at first TUN connect)"
    else
        sudo -n env PLUGIN_USER="$PLUGIN_USER" PLUGIN_DIR="$PLUGIN_DIR" bash -c "$(declare -f install_root_parts); install_root_parts" 2>/dev/null \
            || echo "warn: root helpers/units not installed (will prompt at first TUN connect)"
    fi
    echo "TUN units installed (best-effort, root-owned helpers)."
fi

echo "omarchy-v2ray-manager installed."
echo "CLI: $CLI_DST"
echo "Proxy units: user-level (already active)"
echo "TUN units: system-level (installed on first TUN use)"
