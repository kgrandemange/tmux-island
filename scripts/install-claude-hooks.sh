#!/usr/bin/env bash
# Plugs TmuxIsland's hooks into Claude Code (merges into ~/.claude/settings.json, after making a backup).
set -euo pipefail
command -v jq >/dev/null || { echo "jq is required: brew install jq"; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
bin="$HOME/.local/bin"; mkdir -p "$bin"
cp "$here/tmux-island-hook" "$bin/tmux-island-hook"; chmod +x "$bin/tmux-island-hook"

settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || { echo '{}' > "$settings"; chmod 600 "$settings"; }
backup="$settings.bak.$(date +%s)"
cp -p "$settings" "$backup"          # -p keeps the original permissions (the file may hold secrets)

hook="$bin/tmux-island-hook"
tmp="$(mktemp "$settings.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
# The command is run through a shell by Claude Code: quote the path in case it contains spaces.
jq --arg h "$hook" '
  def entry($s): [{hooks:[{type:"command", command:("\"" + $h + "\" " + $s)}]}];
  def add($ev; $s): .hooks[$ev] = ((.hooks[$ev] // []) | map(select((.hooks // []) | all(.command | tostring | contains("tmux-island-hook") | not)))) + entry($s);
  .hooks = (.hooks // {})
  | add("UserPromptSubmit"; "working")
  | add("PostToolUse"; "working")
  | add("Notification"; "waiting")
  | add("Stop"; "done")
  | add("SessionEnd"; "end")
' "$settings" > "$tmp"
chmod "$(stat -f %Lp "$settings")" "$tmp"   # keep the same permissions as the original file
mv "$tmp" "$settings"
trap - EXIT

echo "✓ hook installed: $hook"
echo "✓ Claude Code hooks added to $settings (backup: $backup)"
echo
echo "Codex (optional): add this to ~/.codex/config.toml"
echo "  notify = [\"$hook\", \"codex\"]"
echo "Restart your Claude Code sessions to pick up the hooks."
