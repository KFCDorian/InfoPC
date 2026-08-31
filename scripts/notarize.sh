#!/bin/bash
# Signe avec un Developer ID, notarise chez Apple et agrafe le ticket.
#
# À utiliser le jour où un certificat Apple Developer (99 $/an) est disponible :
# c'est ce qui supprime l'avertissement de Gatekeeper et, surtout, empêche qu'un
# programme malveillant modifie l'app puis repose une signature ad-hoc.
#
# Prérequis, une fois pour toutes :
#   1. Certificat « Developer ID Application » installé dans le trousseau
#   2. Profil notarytool enregistré :
#      xcrun notarytool store-credentials infopc-notary \
#          --apple-id <votre-apple-id> --team-id <TEAMID> --password <mdp-app-spécifique>
#
# Usage : INFOPC_IDENTITY="Developer ID Application: Nom (TEAMID)" ./scripts/notarize.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
DIST="dist"
APP="$DIST/InfoPC.app"
ZIP="$DIST/InfoPC-$VERSION.zip"
PROFILE="${INFOPC_NOTARY_PROFILE:-infopc-notary}"

IDENTITY="${INFOPC_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"

if [[ -z "$IDENTITY" ]]; then
    cat >&2 <<'EOF'
Aucun certificat « Developer ID Application » trouvé.

Tant qu'il n'y en a pas, la distribution reste en signature ad-hoc :
utilisez ./scripts/package.sh. Ce script-ci n'a rien à faire.
EOF
    exit 1
fi

echo "▸ Identité : $IDENTITY"
./scripts/make-bundle.sh "$APP"

# Signature réelle, par l'intérieur : le binaire imbriqué d'abord, sinon le
# sceau de l'app ne le couvre pas. --options runtime est exigé par la
# notarisation ; --timestamp horodate la signature chez Apple.
echo "▸ Signature Developer ID…"
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP/Contents/MacOS/infopc-fanctl"
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"

echo "▸ Envoi à Apple pour notarisation (quelques minutes)…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# L'agrafage colle le ticket dans le bundle : Gatekeeper l'accepte alors même
# hors ligne. Le zip doit être refait après, pour embarquer le ticket.
echo "▸ Agrafage du ticket…"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "Archive notariée : $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo "SHA-256 : $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "Pensez à retirer le postflight xattr du cask Homebrew : il n'a plus lieu d'être."
