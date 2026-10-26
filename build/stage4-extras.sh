#!/bin/bash
# Stage 4 (im chroot): Chromium (deb aus xtradeb-PPA, kein Snap), WLAN, Claude Code, opencode.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
U=gpu; H=/home/$U

# --- Netzwerk/Tools (NetworkManager ist schon da; WLAN braucht wpasupplicant)
apt-get update
apt-get -y install wpasupplicant curl git ripgrep unzip

# --- Chromium: Ubuntu liefert nur Snap (geht im chroot/offline nicht) -> xtradeb/apps
# Pinning: aus dem PPA NUR chromium*-Pakete, alles andere bleibt Ubuntu.
curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5301FA4FD93244FBC6F6149982BB6851C64F6880' \
    | gpg --dearmor > /usr/share/keyrings/xtradeb-apps.gpg
cat > /etc/apt/sources.list.d/xtradeb-apps.sources <<'EOF'
Types: deb
URIs: https://ppa.launchpadcontent.net/xtradeb/apps/ubuntu
Suites: resolute
Components: main
Signed-By: /usr/share/keyrings/xtradeb-apps.gpg
EOF
cat > /etc/apt/preferences.d/xtradeb-only-chromium <<'EOF'
Package: *
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: -1

Package: chromium chromium-*
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 600
EOF
apt-get update
apt-get -y install chromium
# Chromium ohne Erststart-Dialoge/Keyring-Abfrage
install -d /etc/chromium/policies/managed
cat > /etc/chromium/policies/managed/gpucheck.json <<'EOF'
{ "DefaultBrowserSettingEnabled": false, "PromotionalTabsEnabled": false,
  "MetricsReportingEnabled": false, "BrowserSignin": 0 }
EOF
install -d /etc/chromium.d
echo 'export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --password-store=basic --no-first-run"' > /etc/chromium.d/gpucheck
update-alternatives --set x-www-browser /usr/bin/chromium 2>/dev/null || true
sudo -u $U xdg-settings set default-web-browser chromium.desktop 2>/dev/null || true

# --- Claude Code (nativer Installer, landet in ~/.local/bin) und opencode (~/.opencode/bin)
sudo -u $U -H bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
sudo -u $U -H bash -c 'curl -fsSL https://opencode.ai/install | bash'
# global im PATH (auch für sudo/Textmodus)
ln -sf $H/.local/bin/claude /usr/local/bin/claude
ln -sf $H/.opencode/bin/opencode /usr/local/bin/opencode

apt-get clean
echo "--- Versionen"
chromium --version || true
sudo -u $U -H $H/.local/bin/claude --version || true
sudo -u $U -H $H/.opencode/bin/opencode --version || true
echo "STAGE4 OK"
