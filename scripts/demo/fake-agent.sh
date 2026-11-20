#!/usr/bin/env bash
# Faux agent IA pour la démo : imite l'écran de Claude Code / Codex et signale son état via tmux-island-hook.
# Usage : fake-agent.sh <api|infra|web>   (lancé par demo.sh dans un pane du serveur tmux de démo)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATE="${TMPDIR:-/tmp}/tmuxisland-demo"
HOOK="$ROOT/scripts/tmux-island-hook"
SCENARIO="${1:-api}"

hook() { "$HOOK" "$1" "${2:-claude}" <<< "${3:-{\}}"; }
now() { date +%s; }

case "$SCENARIO" in
  api)   AGENT=claude; TITLE="Refactoring invoice totals";   F1="src/invoice/totals.ts"; F2="src/invoice/discounts.ts" ;;
  web)   AGENT=claude; TITLE="Wiring the checkout form";     F1="src/checkout/Form.tsx"; F2="src/checkout/useCart.ts" ;;
  infra) AGENT=codex;  TITLE="terraform apply (staging)";    F1="staging/main.tf";       F2="staging/network.tf" ;;
esac

working() {   # working <secondes écoulées> <jetons>
  local s=$1 tok=$2
  printf '\033[H\033[2J'
  printf '● Update(%s)\n  ⎿  Updated %s with 6 additions and 2 removals\n' "$F1" "$F1"
  printf '● Bash(npm test -- %s)\n  ⎿  PASS  %s.test.ts (12 tests)\n     Tests: 12 passed, 12 total\n' "$SCENARIO" "$SCENARIO"
  printf '● Read(%s)\n\n' "$F2"
  printf '\033[33m✻ %s… (%dm %02ds · ↓ %s.%sk tokens · esc to interrupt)\033[0m\n\n' "$TITLE" $((s/60)) $((s%60)) $((tok/10)) $((tok%10))
  printf '╭────────────────────────────────────────────╮\n│ >                                          │\n╰────────────────────────────────────────────╯\n'
  printf '  ▸▸ accept edits on (shift+tab to cycle)\n'
}

permission() {
  printf '\033[H\033[2J'
  printf '● Bash(npm run build && npm test)\n  ⎿  Running…\n\n'
  printf '╭────────────────────────────────────────────────────────╮\n'
  printf '│ Bash command                                           │\n'
  printf '│   npm run build && npm test                            │\n'
  printf '│ Do you want to proceed?                                │\n'
  printf '│ ❯ 1. Yes                                               │\n'
  printf '│   2. Yes, and don'"'"'t ask again for npm commands          │\n'
  printf '│   3. No, and tell Claude what to do differently (esc)  │\n'
  printf '╰────────────────────────────────────────────────────────╯\n'
}

done_screen() {  # done_screen <ligne1> <ligne2>
  printf '\033[H\033[2J'
  printf '%s\n%s\n\n❯ \n' "$1" "$2"
}

hook working "$AGENT"
T0=0; tok=18
# Avant le « top départ » : l'agent travaille (point orange), prêt à jouer.
while [ ! -f "$STATE/go" ]; do
  working 52 "$tok"; tok=$((tok+1)); sleep 1
done
T0=$(now)
el() { echo $(( $(now) - T0 )); }

case "$SCENARIO" in
  api)     # travaille en continu, du début à la fin
    while true; do working $((52 + $(el))) "$tok"; tok=$((tok+2)); sleep 1; done ;;
  infra)   # termine après ~9 s : toast « terminé »
    while [ "$(el)" -lt 9 ]; do working $((30 + $(el))) "$tok"; tok=$((tok+1)); sleep 1; done
    done_screen "Apply complete! Resources: 3 added, 1 changed, 0 destroyed." "✔ Staging environment is up to date."
    hook done "$AGENT"
    sleep 3600 ;;
  web)     # demande une permission après ~24 s, attend un chiffre, poursuit, puis termine
    while [ "$(el)" -lt 24 ]; do working $((40 + $(el))) "$tok"; tok=$((tok+1)); sleep 1; done
    permission
    hook waiting "$AGENT" '{"message":"Claude needs your permission to use Bash"}'
    while true; do
      read -rsn1 key
      case "$key" in 1|2|3) break ;; esac
    done
    if [ "$key" = 3 ]; then
      done_screen "⎿ Interrupted · What should Claude do instead?" ""
      hook done "$AGENT"; sleep 3600
    fi
    hook working "$AGENT"
    T1=$(now)
    while [ $(( $(now) - T1 )) -lt 6 ]; do working $((70 + $(el))) "$tok"; tok=$((tok+1)); sleep 1; done
    done_screen "✔ Build succeeded in 8.2s" "✔ 42 tests passed — checkout form is wired."
    hook done "$AGENT"
    sleep 3600 ;;
esac
