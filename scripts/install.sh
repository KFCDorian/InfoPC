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

"$PROJECT_DIR/scripts/make-bundle.sh" "$APP"

if [[ "${1:-}" != "--app" ]]; then
    echo "▸ Installation du helper ventilateurs (sudo requis)…"
    sudo "$APP/Contents/Resources/install-helper.sh"
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
