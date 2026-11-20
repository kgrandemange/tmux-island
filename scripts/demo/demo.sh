#!/usr/bin/env bash
# Environnement de démo isolé pour filmer TmuxIsland sans exposer tes vraies sessions.
#   ./scripts/demo/demo.sh start        prépare tout (serveur tmux fictif, fenêtre de terminal, île en mode démo)
#   ./scripts/demo/demo.sh play [N]     lance le scénario dans N secondes (défaut 8) : le temps d'appuyer sur ⇧⌘5
#   ./scripts/demo/demo.sh stop         nettoie tout et relance ta vraie app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOCK=tmuxisland-demo
STATE="${TMPDIR:-/tmp}/tmuxisland-demo"
APP="$HOME/Applications/TmuxIsland.app/Contents/MacOS/TmuxIsland"
TMUX_BIN="$(command -v tmux || echo /opt/homebrew/bin/tmux)"
T() { "$TMUX_BIN" -L "$SOCK" "$@"; }
HOOK_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-island"

stop_all() {
  pkill -f "TmuxIsland --demo-server" 2>/dev/null || true
  T kill-server 2>/dev/null || true
  rm -f "$HOOK_DIR/${SOCK}__"*.json 2>/dev/null || true
}

case "${1:-}" in
start)
  [ -x "$APP" ] || { echo "App non installée : lance d'abord ./scripts/install.sh"; exit 1; }
  pgrep -x TmuxIsland >/dev/null && touch "$STATE.was-running" || rm -f "$STATE.was-running"
  pkill -x TmuxIsland 2>/dev/null || true; sleep 1
  stop_all; rm -rf "$STATE"; mkdir -p "$STATE"/{shop-api,shop-web,shop-infra}
  A="bash $ROOT/scripts/demo/fake-agent.sh"
  SH="env PS1='\$ ' bash --noprofile --norc -i"
  T new-session -d -s api   -n payments    -c "$STATE/shop-api"   -x 200 -y 50 "$A api"
  T new-window  -t api      -n tests       -c "$STATE/shop-api"   "echo '\$ npm test'; echo 'PASS  12 suites, 84 tests'; exec $SH"
  T new-window  -t api      -n logs        -c "$STATE/shop-api"   "exec $SH"
  T new-session -d -s infra -n terraform   -c "$STATE/shop-infra" -x 200 -y 50 "$A infra"
  T new-window  -t infra    -n k9s         -c "$STATE/shop-infra" "exec $SH"
  T new-session -d -s web   -n editor      -c "$STATE/shop-web"   -x 200 -y 50 "exec $SH"
  T new-window  -t web      -n checkout-ui -c "$STATE/shop-web"   "$A web"
  T new-window  -t web      -n storybook   -c "$STATE/shop-web"   "exec $SH"
  T new-window  -t web      -n e2e         -c "$STATE/shop-web"   "exec $SH"
  T select-window -t web:checkout-ui; T select-window -t api:payments; T select-window -t infra:terraform
  T set -g status-left "[#S] "; T set -g status-left-length 20
  # Fenêtre de terminal attachée à la session « api » (WezTerm si présent, sinon Terminal.app)
  if [ -d /Applications/WezTerm.app ]; then
    open -n -b com.github.wez.wezterm --args start -- "$TMUX_BIN" -L "$SOCK" attach-session -t api
  else
    osascript -e "tell application \"Terminal\" to do script \"$TMUX_BIN -L $SOCK attach-session -t api\"" -e 'tell application "Terminal" to activate'
  fi
  nohup "$APP" --demo-server "$SOCK" >/dev/null 2>&1 &
  echo $! > "$STATE/app.pid"
  sleep 2
  echo "✓ Démo prête : serveur tmux « $SOCK », île en mode démo (tes vraies sessions sont masquées)."
  echo "  Lis scripts/demo/SHOOTING.md puis : ./scripts/demo/demo.sh play 8"
  ;;
play)
  delay="${2:-8}"
  [ -d "$STATE" ] || { echo "Lance d'abord : ./scripts/demo/demo.sh start"; exit 1; }
  rm -f "$STATE/go"
  echo "Scénario dans $delay s… (lance l'enregistrement d'écran avec ⇧⌘5 maintenant)"
  for i in $(seq "$delay" -1 1); do printf '%s… ' "$i"; sleep 1; done; echo "GO"
  touch "$STATE/go"
  ;;
stop)
  stop_all
  was=0; [ -f "$STATE.was-running" ] && was=1
  rm -rf "$STATE" "$STATE.was-running"
  [ "$was" = 1 ] && open "$HOME/Applications/TmuxIsland.app" || true
  echo "✓ Démo arrêtée et nettoyée$([ "$was" = 1 ] && echo ' ; ta vraie app est relancée')."
  ;;
*) sed -n '2,6p' "$0"; exit 1 ;;
esac
