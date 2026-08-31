#!/bin/bash
# Fabrique l'archive distribuable : dist/InfoPC-<version>.zip + son SHA-256
# (celui qu'attend la formule Homebrew).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
DIST="dist"
ZIP="$DIST/InfoPC-$VERSION.zip"

rm -rf "$DIST"
mkdir -p "$DIST"
./scripts/make-bundle.sh "$DIST/InfoPC.app"

# ditto plutôt que zip : c'est l'outil d'Apple, il préserve les attributs
# étendus et la signature du bundle.
ditto -c -k --sequesterRsrc --keepParent "$DIST/InfoPC.app" "$ZIP"

# L'empreinte accompagne l'archive : sans notarisation, c'est le seul moyen
# pour qui télécharge de vérifier qu'il a bien le fichier publié.
( cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS )

echo
echo "Archive : $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo "SHA-256 : $(cut -d' ' -f1 "$DIST/SHA256SUMS")"
