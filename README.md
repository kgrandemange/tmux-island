# TmuxIsland

Une « Dynamic Island » pour la notch du Mac (dans l'esprit d'[Atoll](https://github.com/Ebullioscopic/Atoll)),
dédiée à **tmux et aux agents IA** (Claude Code, Codex, Gemini CLI, OpenCode, Aider…).

Quand un agent a fini ou attend une validation, l'île se déplie, joue un son, et **un clic t'amène
directement sur le bon pane** : `select-window` + `select-pane` + `switch-client` côté tmux, puis mise
au premier plan du bon terminal/onglet (WezTerm via `wezterm cli`, iTerm2 et Terminal.app via AppleScript
sur le tty ; autres terminaux : activation de l'app).

## Fonctionnalités

- **Île compacte** autour de la notch : pastille orange = agents en cours, badges rouge/vert = à valider / terminé.
- **Survol** (ou `⌃⌥Space`) : liste des agents à traiter, triés par urgence, avec état, durée, projet et dernière ligne.
- **Un clic** sur une ligne → le bon pane, le bon onglet. `1`–`9` pour y aller au clavier, `J` pour le prochain à traiter.
- **`⌃⌥J` global** : saute directement au prochain agent terminé / en attente (file d'attente, le plus ancien d'abord).
- **Valider (↵)** une demande de permission et **répondre** depuis l'île sans changer de fenêtre (`tmux send-keys`).
- **Auto-acquittement** : un « terminé » disparaît quand tu regardes déjà le pane.
- **Sessions** : toutes tes sessions/fenêtres tmux en chips cliquables (pastille d'état si un agent y tourne).
- Détection d'un `Esc` (interruption) sans hook `Stop` en recoupant avec l'écran du pane.

## Installation

```bash
./scripts/bundle.sh            # construit build/TmuxIsland.app
open build/TmuxIsland.app      # agent de barre de menus, pas d'icône Dock
./scripts/install-claude-hooks.sh   # (recommandé) hooks précis pour Claude Code, sauvegarde settings.json
```

Sans hooks, l'app fonctionne déjà par heuristique (processus + contenu de l'écran : `esc to interrupt`,
`Do you want to…`). Les hooks rendent « terminé / en attente » instantanés et fiables.

Codex : dans `~/.codex/config.toml` → `notify = ["~/.local/bin/tmux-island-hook", "codex"]`.

Debug : `.build/release/TmuxIsland --snapshot out.png` rend l'île dans un PNG.

## Architecture

| Fichier | Rôle |
|---|---|
| `TmuxService.swift` | tmux (panes, clients, capture), table des processus, lecture des hooks |
| `AgentStore.swift` | polling 1 s, machine à états par pane (working/waiting/done/idle), alertes |
| `FocusService.swift` | saut vers le pane + activation du terminal |
| `IslandController.swift` | panneau non-activant sur la notch, survol, raccourcis |
| `IslandView.swift` | UI SwiftUI |
| `scripts/tmux-island-hook` | écrit l'état dans `~/.local/state/tmux-island/<pane>.json` |

Non testé : iTerm2 / Terminal.app / Ghostty (développé sous WezTerm).
