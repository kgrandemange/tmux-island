#!/usr/bin/env bash
# Branche les hooks Claude Code sur TmuxIsland (fusionne dans ~/.claude/settings.json, avec sauvegarde).
set -euo pipefail
command -v jq >/dev/null || { echo "jq requis : brew install jq"; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
bin="$HOME/.local/bin"; mkdir -p "$bin"
cp "$here/tmux-island-hook" "$bin/tmux-island-hook"; chmod +x "$bin/tmux-island-hook"

settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak.$(date +%s)"

hook="$bin/tmux-island-hook"
jq --arg h "$hook" '
  def entry($s): [{hooks:[{type:"command", command:($h + " " + $s)}]}];
  def add($ev; $s): .hooks[$ev] = ((.hooks[$ev] // []) | map(select((.hooks // []) | all(.command | tostring | contains("tmux-island-hook") | not)))) + entry($s);
  .hooks = (.hooks // {})
  | add("UserPromptSubmit"; "working")
  | add("PostToolUse"; "working")
  | add("Notification"; "waiting")
  | add("Stop"; "done")
  | add("SessionEnd"; "end")
' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"

echo "✓ hook installé : $hook"
echo "✓ hooks Claude Code ajoutés dans $settings (sauvegarde .bak.*)"
echo
echo "Codex (optionnel) — ajoute dans ~/.codex/config.toml :"
echo "  notify = [\"$hook\", \"codex\"]"
echo "Relance tes sessions Claude Code pour prendre en compte les hooks."
