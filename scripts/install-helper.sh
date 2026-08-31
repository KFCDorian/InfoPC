#!/bin/bash
# Installe le helper privilégié des ventilateurs.
#
# Exécuté en root : soit par scripts/install.sh (sudo), soit par l'app
# elle-même via le dialogue de mot de passe de macOS (bouton « Activer le
# contrôle des ventilateurs »). Il vit dans InfoPC.app/Contents/Resources afin
# d'être disponible sur une installation par Homebrew ou par glisser-déposer.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être lancé en root (sudo)." >&2
    exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
# Depuis le bundle : Contents/Resources → Contents/MacOS. Depuis le dépôt :
# scripts/ → .build/release.
for candidate in "$HERE/../MacOS/infopc-fanctl" "$HERE/../.build/release/fanctl"; do
    if [[ -x "$candidate" ]]; then SOURCE="$candidate"; break; fi
done
if [[ -z "${SOURCE:-}" ]]; then
    echo "Binaire fanctl introuvable." >&2
    exit 1
fi

install -m 755 -o root -g wheel "$SOURCE" /usr/local/bin/infopc-fanctl

# La règle est délibérément limitée à ce seul binaire : l'app ne gagne aucun
# autre pouvoir. On valide avant de poser le fichier — un sudoers invalide
# rendrait sudo inutilisable sur la machine.
RULE=$(mktemp)
trap 'rm -f "$RULE"' EXIT
echo "%admin ALL=(root) NOPASSWD: /usr/local/bin/infopc-fanctl" > "$RULE"
visudo -cqf "$RULE"
install -m 440 -o root -g wheel "$RULE" /etc/sudoers.d/infopc

echo "Helper installé : /usr/local/bin/infopc-fanctl"
