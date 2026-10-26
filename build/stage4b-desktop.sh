#!/bin/bash
# Stage 4b (im chroot): LAN über NetworkManager, Desktop-Starter für Chromium/Claude/opencode.
set -euo pipefail
U=gpu; H=/home/$U
# Ubuntu-NM verwaltet ohne Netplan-Datei nur WLAN -> alles an NetworkManager übergeben
printf 'network:\n  version: 2\n  renderer: NetworkManager\n' > /etc/netplan/01-network-manager-all.yaml
chmod 600 /etc/netplan/01-network-manager-all.yaml
: > /etc/NetworkManager/conf.d/10-globally-managed-devices.conf
mk_launcher() {  # datei name icon exec
    printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=%s\nIcon=%s\nExec=%s\nTerminal=false\n' "$2" "$3" "$4" > "$H/Desktop/$1.desktop"
    chmod 755 "$H/Desktop/$1.desktop"
}
mk_launcher 7-chromium "Chromium (Browser)" chromium 'chromium'
mk_launcher 8-claude "Claude Code (Fehlersuche)" utilities-terminal-symbolic \
    'xfce4-terminal --maximize --title="Claude Code" --working-directory=/home/gpu -x claude'
mk_launcher 9-opencode "opencode" utilities-terminal-symbolic \
    'xfce4-terminal --maximize --title=opencode --working-directory=/home/gpu -x opencode'
chown -R $U:$U $H
echo "STAGE4b OK"
