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
  - `SystemStats.swift` — CPU global + **par cœur** (host_processor_info ; P/E via `hw.perflevel0/1.logicalcpu`), GPU (IORegistry `Device Utilization %`), RAM (vm_statistics64), **disque** (URLResourceValues), **réseau** (`getifaddrs` AF_LINK, delta d'octets → débit), températures SMC. Puissance système via clé SMC `PSTR` (le M5 n'expose pas de watts CPU/GPU séparés).
  - `Formatting.swift` — helpers Mbps / Go.
  - Barre de menus **personnalisable** : `MenuBarItem` (cpu/gpu/ram/network/temperature) coché dans le popover, persisté dans UserDefaults. Debug : `InfoPC --sys-debug` (icônes + cœurs).
  - `Processes.swift` — top processus via `/bin/ps -Ao pid,pcpu,pmem,comm`, tri par (CPU+mém), icônes via `NSRunningApplication`/`NSWorkspace`, `kill(pid, SIGTERM)`. **GPU par processus non exposé par macOS** → colonne affichée « — ».
  - `ClaudeUsageAPI.swift` — **source prioritaire des limites Claude** : endpoint OAuth non documenté `GET https://api.anthropic.com/api/oauth/usage` (celui qui alimente `/usage`). Token lu dans le Trousseau (`security find-generic-password -s "Claude Code-credentials" -w` → `claudeAiOauth.accessToken`). Headers requis : `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<version>` (le préfixe `claude-code/` est ce qui compte ; sans lui → 429). Renvoie `five_hour.utilization` (% réel du plan) + `resets_at`, et `seven_day`. Intervalle sûr : 180 s. Debug : `./.build/release/InfoPC --claude-debug`.
  - `ClaudeUsage.swift` — **repli local** si l'API est injoignable : parse `~/.claude/projects/**/*.jsonl`, blocs de 5 h façon ccusage, dénominateur = plus gros bloc historique (`--token-limit max`).
  - `StatsModel.swift` — ObservableObject, timers 2 s (capteurs + rendu barre) / 3 s (processus) / ~60 s (Claude). Rend `MenuBarGaugesView` en `NSImage` (barre de menus n'accepte que texte/image).
  - `BatteryGauge.swift` — barre arrondie qui se remplit (sans borne). `gaugeColor(forPercent:)` disponible mais les jauges sont actuellement en blanc.
  - `MenuBarGaugesView.swift` — jauges compactes CPU/GPU/RAM (titre au-dessus, remplissage blanc, température à droite) pour la barre de menus.
  - `MenuView.swift` — popover (style `.window` pour les sliders), inclut le tableau des processus avec bouton KILL (`ProcCols` = largeurs de colonnes partagées).
- `Sources/fanctl/` — CLI privilégié installé dans `/usr/local/bin/infopc-fanctl` ; l'app l'appelle via `sudo -n` (règle NOPASSWD dans `/etc/sudoers.d/infopc`).

## Spécificités Apple Silicon (testé sur M5, Mac17,2)

- Capteurs temp : clés SMC préfixe `Tp` (CPU) / `Tg` (GPU), type `flt ` (float little-endian). On affiche le capteur le plus chaud.
- Ventilateurs : `FNum` (nombre), `F0Ac` (RPM actuel), `F0Mn`/`F0Mx` (bornes), `F0Tg` (cible). La clé de mode est `F0md` en **minuscules** (pas `F0Md` comme sur Intel).
- L'écriture SMC (contrôle ventilateur) exige root — d'où le helper.

## Déploiement

- Bundle : `~/Applications/InfoPC.app` (LSUIElement, pas d'icône Dock), signature ad-hoc.
- Démarrage auto : LaunchAgent `~/Library/LaunchAgents/com.kfcdorian.infopc.plist` (RunAtLoad + KeepAlive sauf sortie propre).
