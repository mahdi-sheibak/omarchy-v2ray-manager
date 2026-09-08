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

# Helper scripts referenced by TUN units — deployed into CONFIG_DIR.
CONF_DIR="$HOME/.config/v2ray-manager"
mkdir -p "$CONF_DIR"
for script in tun-start.sh tun-stop.sh xray-tun-setup.sh; do
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
# TUN units reference the user's config path; rewrite /home/mahdi → $HOME.
# BEST-EFFORT: if root install fails here (no TTY for pkexec/sudo when
# spawned from Quickshell), we continue — the CLI falls back to
# `pkexec systemctl start` at first TUN connect, which shows a GUI prompt
# at the right moment. Blocking the whole installer on this breaks
# auto-install on fresh machines (CLI already copied by then).
have_pkexec() { command -v pkexec >/dev/null 2>&1; }

units_needed=0
for unit in omarchy-v2ray-tun.service omarchy-v2ray-xray-tun.service; do
    [ -f "/etc/systemd/system/$unit" ] || units_needed=1
done

if [ "$units_needed" = "1" ]; then
    echo "TUN units missing. Installing requires root (polkit prompt):"
    for unit in omarchy-v2ray-tun.service omarchy-v2ray-xray-tun.service; do
        src="$PLUGIN_DIR/systemd/$unit"
        tmp="/tmp/$unit.$$"
        sed "s|/home/mahdi|$HOME|g" "$src" > "$tmp"
        if have_pkexec; then
            pkexec cp "$tmp" "/etc/systemd/system/$unit" || echo "warn: could not install $unit (will prompt at first TUN connect)"
        else
            sudo -n cp "$tmp" "/etc/systemd/system/$unit" 2>/dev/null || echo "warn: could not install $unit (will prompt at first TUN connect)"
        fi
        rm -f "$tmp"
    done
    if have_pkexec; then
        pkexec systemctl daemon-reload || sudo -n systemctl daemon-reload 2>/dev/null || true
    else
        sudo -n systemctl daemon-reload 2>/dev/null || true
    fi
    echo "TUN units installed (best-effort)."
fi

echo "omarchy-v2ray-manager installed."
echo "CLI: $CLI_DST"
echo "Proxy units: user-level (already active)"
echo "TUN units: system-level (installed on first TUN use)"
