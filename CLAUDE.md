# InfoPC

App macOS de barre de menus (SwiftUI, sans Xcode — Swift Package pur) affichant en live : usage et température CPU/GPU, RAM, ventilateurs (nombre, RPM, contrôle par slider) et l'usage des limites Claude Code (bloc de 5 h).

## Commandes

```bash
swift build -c release            # compiler
./scripts/install.sh              # installer tout (app + helper sudo + démarrage auto)
./scripts/install.sh --app        # installer sans le helper (pas de sudo)
./scripts/uninstall.sh            # tout désinstaller
./.build/release/fanctl status    # debug : état des ventilateurs
./.build/release/fanctl keys Tp   # debug : lister les clés SMC par préfixe
```

Après modification du code : relancer `./scripts/install.sh --app` (rebuild + redéploiement du bundle + relance via launchctl).

## Architecture

- `Sources/SMCCore/` — client AppleSMC (IOKit) partagé : lecture capteurs, énumération des clés, écriture ventilateurs. **Attention** : la struct `SMCKeyData` doit faire exactement 80 octets (padding explicite dans `SMCKeyInfo` — Swift ne padde pas comme le C).
- `Sources/InfoPC/` — l'app MenuBarExtra :
  - `SystemStats.swift` — CPU (host_processor_info), GPU (IORegistry `PerformanceStatistics` → `Device Utilization %`), RAM (vm_statistics64), températures SMC.
  - `ClaudeUsage.swift` — parse `~/.claude/projects/**/*.jsonl`, reconstitue le bloc de 5 h courant (aligné à l'heure pleine, comme ccusage). Limite auto-calibrée dans UserDefaults.
  - `StatsModel.swift` — ObservableObject, timers 2 s (capteurs) / 60 s (Claude).
  - `MenuView.swift` — popover (style `.window` pour les sliders).
- `Sources/fanctl/` — CLI privilégié installé dans `/usr/local/bin/infopc-fanctl` ; l'app l'appelle via `sudo -n` (règle NOPASSWD dans `/etc/sudoers.d/infopc`).

## Spécificités Apple Silicon (testé sur M5, Mac17,2)

- Capteurs temp : clés SMC préfixe `Tp` (CPU) / `Tg` (GPU), type `flt ` (float little-endian). On affiche le capteur le plus chaud.
- Ventilateurs : `FNum` (nombre), `F0Ac` (RPM actuel), `F0Mn`/`F0Mx` (bornes), `F0Tg` (cible). La clé de mode est `F0md` en **minuscules** (pas `F0Md` comme sur Intel).
- L'écriture SMC (contrôle ventilateur) exige root — d'où le helper.

## Déploiement

- Bundle : `~/Applications/InfoPC.app` (LSUIElement, pas d'icône Dock), signature ad-hoc.
- Démarrage auto : LaunchAgent `~/Library/LaunchAgents/com.kfcdorian.infopc.plist` (RunAtLoad + KeepAlive sauf sortie propre).
