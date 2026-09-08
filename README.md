# v2ray-manager for Omarchy

VLESS/VMESS proxy and TUN VPN manager for the Omarchy bar. Toggle proxy or full TUN mode, switch between sing-box and xray-core backends, manage profiles and subscriptions, import share links, and watch live traffic on a sparkline — all from one bar icon and popup panel.

![Omarchy](https://img.shields.io/badge/Omarchy-Quattro-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Bar widget** — connection status icon with color states (disconnected / proxy / TUN)
- **Popup panel** — connect, disconnect, switch backend (sing-box or xray-core), switch Proxy ↔ TUN mode
- **Profile management** — add, remove, and switch between proxy profiles
- **Subscription support** — fetch V2Ray/Clash subscription URLs, auto-refetch on a configurable interval
- **Share-link import** — paste `vless://` / `vmess://` links to add servers
- **Live traffic sparkline** — upload/download rate chart in the panel
- **Health monitoring** — periodic exit-IP health check with optional auto-reconnect
- **Backend choice** — per-profile selection of `sing-box` or `xray-core`

## Requirements

External binaries, installed separately:

| Backend | Package |
|---------|---------|
| sing-box | `pacman -S sing-box` or from [sing-box releases](https://github.com/SagerNet/sing-box/releases) |
| xray-core | `pacman -S xray` or [XTLS/Xray-core releases](https://github.com/XTLS/Xray-core/releases) |

The plugin shells out to these binaries; at least one must be on `PATH`. TUN mode additionally requires root-capable process elevation (polkit or passwordless sudo for the helper script).

Tested on Omarchy (Arch Linux + Hyprland + Quickshell). Requires Omarchy Quattro or newer shell with plugin support.

## Installation

```bash
omarchy plugin add https://github.com/mahdi-sheibak/omarchy-v2ray-manager.git --enable --yes
```

Then add **V2Ray** to your bar layout (right section recommended) via `omarchy bar` or by editing `~/.config/omarchy/shell.json`:

```json
{ "id": "mahdi.v2ray-manager" }
```

## Removal

```bash
omarchy plugin remove mahdi.v2ray-manager --yes
```

Then delete any leftover bar entry from `~/.config/omarchy/shell.json` and restart the shell if needed:

```bash
omarchy restart shell
```

## Configuration

Widget settings (via Omarchy plugin settings UI or `shell.json`):

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `refreshIntervalSec` | integer (5–300) | 30 | Status refresh interval in seconds |
| `subscriptionRefetchMin` | integer (0–1440) | 360 | Auto-refetch subscriptions; 0 disables |
| `autoReconnect` | boolean | true | Reconnect automatically when health check fails |

Profiles and their backend/mode settings are managed in the panel UI and stored by the plugin's service layer.

## How it works

- `BarWidget.qml` — bar icon, status color, click opens panel
- `Panel.qml` — full control panel (connect, profiles, backend, mode, share-link import, sparkline)
- `Service.qml` — background polling of connection state, subscription refetch, health checks
- `Sparkline.qml` — canvas traffic-rate chart

State and profile data live under the plugin's own config scope; the plugin never edits your existing sing-box/xray configs — it generates its own.

## Privacy & Security Notes

- This plugin manages your own proxy servers/subscription URLs. No telemetry, no analytics.
- Subscription URLs and server credentials stay on your machine.
- Proxy tool usage may be restricted or illegal in some jurisdictions. You are responsible for complying with local laws.

## License

MIT — see [LICENSE](LICENSE).
