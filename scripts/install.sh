#!/bin/bash
# Installe InfoPC : app de barre de menus + helper ventilateurs + démarrage auto.
# Usage : ./scripts/install.sh          (installation complète, demande sudo)
#         ./scripts/install.sh --app    (app + LaunchAgent seulement, sans sudo)
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
APP="$HOME/Applications/InfoPC.app"
PLIST="$HOME/Library/LaunchAgents/com.kfcdorian.infopc.plist"
BUNDLE_ID="com.kfcdorian.infopc"

echo "▸ Compilation (release)…"
swift build -c release

echo "▸ Création du bundle $APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/InfoPC "$APP/Contents/MacOS/InfoPC"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>InfoPC</string>
    <key>CFBundleExecutable</key><string>InfoPC</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"

if [[ "${1:-}" != "--app" ]]; then
    echo "▸ Installation du helper ventilateurs (sudo requis)…"
    sudo install -m 755 .build/release/fanctl /usr/local/bin/infopc-fanctl
    echo "%admin ALL=(root) NOPASSWD: /usr/local/bin/infopc-fanctl" | sudo tee /etc/sudoers.d/infopc > /dev/null
    sudo chmod 440 /etc/sudoers.d/infopc
    echo "  Helper installé : /usr/local/bin/infopc-fanctl"
fi

echo "▸ Configuration du démarrage automatique…"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${BUNDLE_ID}</string>
    <key>Program</key><string>${APP}/Contents/MacOS/InfoPC</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
</dict>
</plist>
EOF

# (Re)charge l'agent : l'app démarre maintenant et à chaque ouverture de session.
# On attend que launchd libère bien le service avant de le re-bootstrapper,
# sinon bootstrap peut renvoyer « 5: Input/output error ».
launchctl bootout "gui/$(id -u)/${BUNDLE_ID}" 2>/dev/null || true
for _ in 1 2 3 4 5; do
    launchctl print "gui/$(id -u)/${BUNDLE_ID}" >/dev/null 2>&1 || break
    sleep 1
done
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✅ InfoPC installé et lancé. Il démarrera automatiquement à chaque session."
