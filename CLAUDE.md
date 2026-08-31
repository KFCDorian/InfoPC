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
./scripts/package.sh              # fabriquer dist/InfoPC-<version>.zip + SHA-256 (release)
```

La version publiée vit dans le fichier `VERSION` à la racine (lu par `make-bundle.sh`
pour `CFBundleShortVersionString`, par `package.sh` pour le nom de l'archive).

Après modification du code : relancer `./scripts/install.sh --app` (rebuild + redéploiement du bundle + relance via launchctl).

## Architecture

- `Sources/SMCCore/` — client AppleSMC (IOKit) partagé : lecture capteurs, énumération des clés, écriture ventilateurs. **Attention** : la struct `SMCKeyData` doit faire exactement 80 octets (padding explicite dans `SMCKeyInfo` — Swift ne padde pas comme le C).
- `Sources/InfoPC/` — l'app MenuBarExtra :
  - `SystemStats.swift` — CPU global + **par cœur** (host_processor_info ; P/E via `hw.perflevel0/1.logicalcpu`), GPU (IORegistry `Device Utilization %`), RAM (vm_statistics64), **disque** (URLResourceValues), **réseau** (`getifaddrs` AF_LINK, delta d'octets → débit), températures SMC. Puissance système via clé SMC `PSTR` (le M5 n'expose pas de watts CPU/GPU séparés).
  - `Formatting.swift` — helpers Mbps / Go.
  - Barre de menus **personnalisable** : `MenuBarItem` (cpu/gpu/ram/network/temperature) coché dans le popover, persisté dans UserDefaults. Debug : `InfoPC --sys-debug` (icônes + cœurs).
  - `Processes.swift` — top processus via `/bin/ps -Ao pid,pcpu,pmem,comm`, tri par (CPU+mém), icônes via `NSRunningApplication`/`NSWorkspace`, `kill(pid, SIGTERM)`. **GPU par processus non exposé par macOS** → colonne affichée « — ».
  - `ClaudeUsageAPI.swift` — **source prioritaire des limites Claude** : endpoint OAuth non documenté `GET https://api.anthropic.com/api/oauth/usage` (celui qui alimente `/usage`). Token lu dans le Trousseau : le nom du service **n'est pas figé** — historiquement `Claude Code-credentials`, aujourd'hui suffixé par un identifiant d'installation (`Claude Code-credentials-8b9b410d`). On énumère donc les entrées par préfixe (`SecItemCopyMatching`, attributs seuls → pas de demande d'autorisation) puis on lit chaque candidate avec `security find-generic-password -s <nom exact> -w` en gardant la première qui porte `claudeAiOauth.accessToken` : les autres ne contiennent qu'un objet `mcpOAuth` (jetons des serveurs MCP). **Si Claude Code est lancé depuis l'app Claude pour macOS**, aucun jeton n'est écrit là (l'app garde ses identifiants chiffrés via `Claude Safe Storage`) → l'usage réel est indisponible tant qu'on ne s'est pas connecté via le CLI `claude`. Headers requis : `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<version>` (le préfixe `claude-code/` est ce qui compte ; sans lui → 429). Les trois limites (session 5 h, `weekly_all`, `weekly_scoped` par modèle) sont lues dans le tableau `limits` — **seul porteur de `severity`** — avec repli sur les blocs `five_hour`/`seven_day` qui donnent les mêmes chiffres sans la gravité. Chacune devient un `ClaudeLimitState` (percent + resetsAt + severity). `resets_at` est `null` tant qu'une limite n'est pas entamée (`is_active: false`) : afficher « — » est fidèle à la source, pas un bug. Couleur des barres : `gaugeLevel(forSeverity:percent:)` retient le **plus alarmant** entre l'avis du serveur et nos seuils — le vocabulaire de `severity` n'est pas documenté (seul « normal » observé), donc une valeur inconnue est ignorée plutôt que devinée, sans quoi une jauge pleine pourrait s'afficher tranquille. Intervalle sûr : 180 s. Debug : `./.build/release/InfoPC --claude-debug` (affiche la gravité et diagnostique précisément l'absence de jeton).
  - `ClaudeUsage.swift` — **repli local** si l'API est injoignable : parse `~/.claude/projects/**/*.jsonl`, blocs de 5 h façon ccusage, dénominateur = plus gros bloc historique (`--token-limit max`).
  - `StatsModel.swift` — ObservableObject, timers 2 s (capteurs + rendu barre) / 3 s (processus) / ~60 s (Claude). Rend `MenuBarGaugesView` en `NSImage` (barre de menus n'accepte que texte/image).
  - `BatteryGauge.swift` — barre arrondie qui se remplit (sans borne). `gaugeColor(forPercent:)` disponible mais les jauges sont actuellement en blanc.
  - `MenuBarGaugesView.swift` — jauges compactes CPU/GPU/RAM (titre au-dessus, remplissage blanc, température à droite) pour la barre de menus.
  - `MenuView.swift` — popover (style `.window` pour les sliders), inclut le tableau des processus avec bouton KILL (`ProcCols` = largeurs de colonnes partagées).
  - `Theme.swift` — jetons visuels du popover (rayons, marges, contours, fonds) et briques partagées : `SectionCard` (carte à en-tête), `Badge` (pastille), `ProgressBar` (jauge pleine), `CoreBar` (barre d'un cœur). Toute nouvelle section passe par là. **Ne pas y toucher pour la barre de menus** : elle garde `BatteryGauge`, dont le contour est nécessaire pour rester lisible sur fond clair comme sombre.
- `Sources/fanctl/` — CLI privilégié installé dans `/usr/local/bin/infopc-fanctl` ; l'app l'appelle via `sudo -n` (règle NOPASSWD dans `/etc/sudoers.d/infopc`).

## Spécificités Apple Silicon (testé sur M5, Mac17,2)

- Capteurs temp : clés SMC préfixe `Tp` (CPU) / `Tg` (GPU), type `flt ` (float little-endian). On affiche le capteur le plus chaud.
- Ventilateurs : `FNum` (nombre), `F0Ac` (RPM actuel), `F0Mn`/`F0Mx` (bornes), `F0Tg` (cible). La clé de mode est `F0md` en **minuscules** (pas `F0Md` comme sur Intel) : `1` = régime forcé, `0` = le système décide.
- **En mode auto, c'est le SMC qui écrit `F0Tg`** : la cible suit le régime décidé par le système, il ne faut donc jamais figer le curseur sur la dernière valeur forcée (il doit suivre `F0Tg`). Le mode réel se relit dans `F0md` — sans root — plutôt que de se fier à un état supposé côté app.
- Machine froide (≈45 °C), le SMC **arrête complètement le ventilateur** : `F0Ac = 0` et `F0Tg = 0`, sous le minimum `F0Mn`. C'est normal sur Apple Silicon, ce n'est pas une panne.
- L'écriture SMC (contrôle ventilateur) exige root — d'où le helper.

## Déploiement

- Bundle : `~/Applications/InfoPC.app` (LSUIElement, pas d'icône Dock), signature ad-hoc.
  Construit par `scripts/make-bundle.sh <chemin>`, partagé entre l'installation de
  dev (`install.sh`) et l'archive publique (`package.sh`) — on distribue donc
  exactement le bundle qu'on utilise.
- Le bundle **embarque le helper** (`Contents/MacOS/infopc-fanctl`) et son
  installateur (`Contents/Resources/install-helper.sh`) : une installation par
  Homebrew ou par glisser-déposer peut ainsi activer le contrôle des ventilateurs
  sans cloner le dépôt. Le bouton « Activer le contrôle des ventilateurs » du
  popover lance ce script via `osascript … with administrator privileges` (hors du
  thread principal : la saisie du mot de passe ne doit pas figer l'UI). Le script
  valide sa règle avec `visudo -cq` avant de la poser — un sudoers cassé rendrait
  `sudo` inutilisable sur la machine.
- Démarrage auto : LaunchAgent `~/Library/LaunchAgents/com.kfcdorian.infopc.plist` (RunAtLoad + KeepAlive sauf sortie propre).
  **Une installation Homebrew n'en pose pas** : l'app se lance à la main ou via les
  éléments d'ouverture.

## Distribution

- Releases GitHub : archive `.zip` produite par `ditto` (préserve la signature),
  signature **ad-hoc** — Gatekeeper avertit au premier lancement, c'est attendu et
  documenté dans le README (clic droit → Ouvrir, ou `xattr -dr com.apple.quarantine`).
- Cask Homebrew : dépôt `KFCDorian/homebrew-tap`, `Casks/infopc.rb`. Le `postflight`
  retire l'attribut de quarantaine, sinon l'app ad-hoc est bloquée après un
  `brew install --cask`.
- La fonction **Limites Claude est étiquetée « expérimental » dans l'UI** (badge +
  infobulle, `MenuView.experimentalNotice`) : elle repose sur un endpoint non
  documenté et sur le Trousseau, contrairement au reste de l'app. Ne pas la
  présenter comme une garantie, ici ou dans une future offre payante.
