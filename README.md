# InfoPC

Moniteur système dans la barre de menus macOS, pensé pour MacBook Apple Silicon.

**Dans la barre de menus** : `C 42% 55°  G 12% 44°` (usage + température CPU/GPU, mis à jour toutes les 2 s).

**Dans le popover** :

- **CPU / GPU** — usage %, température (capteur le plus chaud), barres colorées (vert / orange / rouge)
- **Mémoire** — RAM utilisée / totale avec barre
- **Ventilateurs** — nombre détecté, ventilateurs actifs, RPM en direct, **slider de contrôle** (min→max) et retour au mode **Auto**
- **Limites Claude** — **usage réel du compte** (session 5 h et semaine) avec pourcentage et heure de réinitialisation, via l'endpoint OAuth `/usage` de Claude Code (le même que la commande `/usage`)

## Installation

```bash
./scripts/install.sh
```

Le script compile, installe l'app dans `~/Applications`, configure le **démarrage automatique** (LaunchAgent) et installe le helper de contrôle des ventilateurs (`sudo` demandé une seule fois — règle NOPASSWD ciblée sur `/usr/local/bin/infopc-fanctl` uniquement).

Sans contrôle des ventilateurs (pas de sudo) : `./scripts/install.sh --app`

## Désinstallation

```bash
./scripts/uninstall.sh
```

## Notes

- Le contrôle des ventilateurs écrit dans le SMC (clés `F0md`/`F0Tg`). Le bouton **Auto** rend la main au système. En cas de doute, laissez le mode Auto : macOS gère très bien ses ventilateurs.
- Les limites Claude affichées sont les **vraies valeurs de votre compte** : l'app lit votre token OAuth dans le Trousseau (comme le fait Claude Code) et interroge `api.anthropic.com/api/oauth/usage`. Le token ne quitte jamais votre machine, sauf vers Anthropic. Si le token est absent/expiré, l'app retombe sur une estimation locale à partir de `~/.claude/projects`.
- Testé sur MacBook Pro M5 (macOS 26). Devrait fonctionner sur tout Mac Apple Silicon.
