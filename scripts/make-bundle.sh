#!/bin/bash
# Construit InfoPC.app à l'emplacement demandé (défaut : ~/Applications).
# Utilisé par install.sh (poste de dev) et par package.sh (release publique) :
# le bundle distribué est exactement celui qu'on utilise au quotidien.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${1:-$HOME/Applications/InfoPC.app}"
VERSION="$(cat VERSION)"
BUNDLE_ID="com.kfcdorian.infopc"

echo "▸ Compilation (release)…"
swift build -c release

echo "▸ Création du bundle $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/InfoPC "$APP/Contents/MacOS/InfoPC"
# Le helper voyage dans le bundle : l'app peut ainsi l'installer elle-même
# après un téléchargement ou un `brew install`, sans cloner le dépôt.
cp .build/release/fanctl "$APP/Contents/MacOS/infopc-fanctl"
cp scripts/install-helper.sh "$APP/Contents/Resources/install-helper.sh"
chmod +x "$APP/Contents/Resources/install-helper.sh"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>InfoPC</string>
    <key>CFBundleExecutable</key><string>InfoPC</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Signature ad-hoc : suffisante pour tourner, mais Gatekeeper avertira au
# premier lancement (pas de certificat Developer ID). Le binaire imbriqué se
# signe avant l'app, sinon le sceau de l'app ne le couvre pas.
codesign --force --sign - "$APP/Contents/MacOS/infopc-fanctl"
codesign --force --sign - "$APP"
