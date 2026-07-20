# InfoPC

Moniteur système dans la barre de menus macOS, pensé pour MacBook Apple Silicon.

**Dans la barre de menus** : `C 42% 55°  G 12% 44°` (usage + température CPU/GPU, mis à jour toutes les 2 s).

**Dans le popover** :

- **CPU / GPU** — usage %, température (capteur le plus chaud), barres colorées (vert / orange / rouge)
- **Mémoire** — RAM utilisée / totale avec barre
- **Ventilateurs** — nombre détecté, ventilateurs actifs, RPM en direct, **slider de contrôle** (min→max) et retour au mode **Auto**
- **Limites Claude** — usage du bloc de 5 h de Claude Code avec barre de progression, heure de réinitialisation, limite auto-calibrée

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
- L'usage Claude est estimé à partir des transcripts locaux `~/.claude/projects` (tous tokens confondus, blocs de 5 h façon ccusage) — c'est une estimation, pas la valeur exacte du serveur Anthropic.
- Testé sur MacBook Pro M5 (macOS 26). Devrait fonctionner sur tout Mac Apple Silicon.
