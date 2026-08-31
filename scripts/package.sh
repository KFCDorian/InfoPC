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

echo
echo "Archive : $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo "SHA-256 : $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
