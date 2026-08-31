# Sécurité

## Signaler une faille

Ouvrez un [avis de sécurité privé](https://github.com/KFCDorian/InfoPC/security/advisories/new)
plutôt qu'une issue publique. Réponse sous quelques jours.

## Ce qu'InfoPC obtient sur votre machine, et pourquoi

| | |
|---|---|
| **Lecture des capteurs** (SMC, IOKit) | aucun privilège particulier |
| **Écriture des ventilateurs** | **exige root** — d'où le helper séparé, décrit plus bas |
| **Liste et arrêt des processus** | vos propres processus, comme le Moniteur d'activité |
| **Trousseau** | une seule entrée lue : le jeton OAuth de Claude Code, si vous en avez un |
| **Réseau** | `api.anthropic.com` (limites Claude) et `speed.cloudflare.com` (uniquement sur clic) |

Aucune télémétrie, aucun compte, aucune donnée d'usage collectée.

## Le helper privilégié

Écrire dans le SMC exige root. Plutôt que de faire tourner toute l'app en root,
InfoPC installe un binaire séparé et minuscule, `infopc-fanctl`, qui ne sait
faire que trois choses : lire l'état des ventilateurs, forcer un régime **borné
aux minimum et maximum déclarés par le matériel**, et rendre la main au système.
Il n'expose aucune écriture SMC arbitraire.

Ce binaire est installé dans `/Library/PrivilegedHelperTools/`, un répertoire que
macOS maintient à `root:wheel`. C'est délibéré : un binaire lancé en root **sans
mot de passe** ne doit être remplaçable que par root. `/usr/local/bin`, utilisé
jusqu'à la version 1.1.0, ne l'assure pas — Homebrew se l'approprie couramment,
et un programme quelconque tournant sous votre compte pouvait alors y obtenir
root sans invite ([corrigé en 1.2.0](https://github.com/KFCDorian/InfoPC/releases/tag/v1.2.0),
mettez à jour si vous êtes en 1.0.0 ou 1.1.0).

L'installateur, avant d'écrire quoi que ce soit :

- remonte **tous** les répertoires du chemin et refuse si l'un d'eux
  n'appartient pas à root ou est modifiable par le groupe ;
- refuse un binaire source qui serait un lien symbolique, ou dont le sceau de
  signature est invalide ;
- valide sa règle `sudoers` avec `visudo` avant de la poser — une règle
  malformée rendrait `sudo` inutilisable sur la machine.

La règle posée vise **un binaire et un compte** :

```
<votre compte> ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/com.kfcdorian.infopc.fanctl
```

Pour tout retirer, sans désinstaller l'app :

```bash
sudo rm -f /Library/PrivilegedHelperTools/com.kfcdorian.infopc.fanctl /etc/sudoers.d/infopc
```

## Limite connue : l'app n'est pas notariée

InfoPC est signée en **ad-hoc**, faute de certificat Apple Developer (99 $/an).
Conséquences, dites franchement :

- macOS avertit au premier lancement, et le cask Homebrew retire lui-même
  l'attribut de quarantaine pour que l'installation aboutisse ;
- un programme malveillant déjà présent sur votre machine peut modifier
  `InfoPC.app` — qui vit dans un dossier où votre compte écrit — et reposer une
  signature ad-hoc. La vérification faite par l'installateur du helper attrape
  une substitution grossière, pas celle-là.

Seule la notarisation Developer ID ferme cette porte. En attendant, vérifiez ce
que vous téléchargez : chaque release publie le SHA-256 de son archive.

## Vérifier une archive téléchargée

```bash
shasum -a 256 InfoPC-1.2.1.zip
```

Le résultat doit correspondre au SHA-256 publié dans les notes de la
[release](https://github.com/KFCDorian/InfoPC/releases) correspondante.
