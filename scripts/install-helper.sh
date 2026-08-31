#!/bin/bash
# Installe le helper privilégié des ventilateurs.
#
# Exécuté en root : soit par scripts/install.sh (sudo), soit par l'app
# elle-même via le dialogue de mot de passe de macOS (bouton « Activer le
# contrôle des ventilateurs »). Il vit dans InfoPC.app/Contents/Resources afin
# d'être disponible sur une installation par Homebrew ou par glisser-déposer.
set -euo pipefail

HELPER_DIR="/Library/PrivilegedHelperTools"
HELPER="$HELPER_DIR/com.kfcdorian.infopc.fanctl"
LEGACY="/usr/local/bin/infopc-fanctl"

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

# Un binaire lancé en root sans mot de passe ne doit être remplaçable que par
# root : si un répertoire du chemin est modifiable par l'utilisateur ou par le
# groupe, la règle sudoers ci-dessous deviendrait une élévation de privilèges
# offerte à n'importe quel programme tournant sous ce compte. C'est le cas
# classique de /usr/local quand Homebrew se l'est approprié — d'où
# /Library/PrivilegedHelperTools, que macOS garde à root:wheel.
assert_root_only() {
    local path="$1"
    while :; do
        local owner mode
        owner="$(stat -f '%Su' "$path")"
        mode="$(stat -f '%OLp' "$path")"
        if [[ "$owner" != "root" ]]; then
            echo "Refus : $path appartient à $owner, pas à root." >&2
            exit 1
        fi
        # Aucun droit d'écriture pour le groupe ni pour les autres.
        if (( (8#$mode & 8#022) != 0 )); then
            echo "Refus : $path est modifiable hors de root (mode $mode)." >&2
            exit 1
        fi
        [[ "$path" == "/" ]] && break
        path="$(dirname "$path")"
    done
}

install -d -m 755 -o root -g wheel "$HELPER_DIR"
assert_root_only "$HELPER_DIR"
install -m 755 -o root -g wheel "$SOURCE" "$HELPER"

# La règle est délibérément limitée à ce seul binaire et au compte qui installe
# — pas à tout le groupe admin, qui sur un Mac partagé désignerait aussi les
# autres administrateurs. On valide avant de poser le fichier : un sudoers
# invalide rendrait sudo inutilisable sur la machine.
USER_NAME="${SUDO_USER:-$(stat -f '%Su' /dev/console)}"
RULE=$(mktemp)
trap 'rm -f "$RULE"' EXIT
echo "$USER_NAME ALL=(root) NOPASSWD: $HELPER" > "$RULE"
visudo -cqf "$RULE"
install -m 440 -o root -g wheel "$RULE" /etc/sudoers.d/infopc

# Installations antérieures à 1.2.0 : le helper vivait dans /usr/local/bin,
# dont le propriétaire n'est pas garanti d'une machine à l'autre.
rm -f "$LEGACY"

echo "Helper installé : $HELPER"
