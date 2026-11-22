#!/bin/bash
# Checks that clicking an agent brings the RIGHT terminal window/tab to the front.
#
# It starts a throwaway tmux server (`tmux -L tmuxisland-focus-test`), opens terminal windows attached to its
# sessions, then runs the real jump code (`TmuxIsland --jump-session`) and asks the terminal which tab is in front.
# Only the windows opened here are touched (and closed at the end); your other windows are left alone.
#
# Terminals: terminal (Apple's Terminal.app), iterm (iTerm2). WezTerm is checked by hand for now.
# Scenarios: several windows (one session each); iTerm2 also checks several tabs in ONE window.
# Not covered (needs Accessibility to open tabs / type keys): tabs in Terminal.app, and one session attached in
# two windows (the most recently typed one wins).
#
# Needs: macOS Automation permission for the terminal (a prompt appears the first time).
# Usage: scripts/check-terminal-focus.sh [terminal|iterm] [path/to/TmuxIsland]   (default: terminal, .build/release/TmuxIsland)
set -u
cd "$(dirname "$0")/.."
KIND="${1:-terminal}"
BIN="${2:-.build/release/TmuxIsland}"
NAME=tmuxisland-focus-test
TMUX_BIN=$(command -v tmux || echo /opt/homebrew/bin/tmux)
[ -x "$BIN" ] || { echo "missing $BIN (run swift build -c release)"; exit 2; }

case "$KIND" in
  terminal) APP="Terminal"; BUNDLE="com.apple.Terminal" ;;
  iterm)    APP="iTerm2";   BUNDLE="com.googlecode.iterm2" ;;
  *) echo "unknown terminal '$KIND' (terminal | iterm)"; exit 2 ;;
esac
[ -n "$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE'" | head -1)" ] || { echo "$APP is not installed"; exit 2; }

fail=0
tt() { "$TMUX_BIN" -L "$NAME" "$@"; }
ATTACH() { echo "$TMUX_BIN -L $NAME attach -t $1"; }

# --- per-terminal AppleScript ---------------------------------------------------------------------------------
# open_window SESSION  -> prints the tty of a new window attached to the session
# open_tab SESSION     -> (iterm only) adds a tab to the last window opened, prints its tty
# front_tty            -> tty of the tab currently in front
# close_tty TTY        -> closes the window holding that tty
if [ "$KIND" = terminal ]; then
  open_window() { osascript -e "tell application \"Terminal\"
      set t to do script \"exec $(ATTACH "$1")\"
      return tty of t
    end tell"; }
  front_tty() { osascript -e 'tell application "Terminal" to return tty of selected tab of front window'; }
  close_tty() { osascript -e "tell application \"Terminal\"
      repeat with w in windows
        repeat with t in tabs of w
          if tty of t is \"$1\" then close w saving no
        end repeat
      end repeat
    end tell" >/dev/null 2>&1; }
else
  open_window() { osascript -e "tell application \"iTerm2\"
      set w to (create window with default profile command \"$(ATTACH "$1")\")
      return tty of current session of current tab of w
    end tell"; }
  open_tab() { osascript -e "tell application \"iTerm2\"
      tell current window
        set t to (create tab with default profile command \"$(ATTACH "$1")\")
        return tty of current session of t
      end tell
    end tell"; }
  front_tty() { osascript -e 'tell application "iTerm2" to return tty of current session of current tab of current window'; }
  close_tty() { osascript -e "tell application \"iTerm2\"
      repeat with w in windows
        repeat with t in tabs of w
          repeat with s in sessions of t
            if tty of s is \"$1\" then close w
          end repeat
        end repeat
      end repeat
    end tell" >/dev/null 2>&1; }
fi

TTYS=()
cleanup() {
  tt kill-server 2>/dev/null
  for tty in "${TTYS[@]:-}"; do [ -n "$tty" ] && close_tty "$tty"; done
}
trap cleanup EXIT

front_session() {
  local tty; tty=$(front_tty)
  tt list-clients -F '#{client_tty} #{client_session}' | awk -v t="$tty" '$1==t {print $2}'
}
front_app() { lsappinfo info -only bundleid "$(lsappinfo front)" | grep -o 'bundleID="[^"]*"' | cut -d'"' -f2; }
check() { # description, expected session
  local got app; got=$(front_session); app=$(front_app)
  if [ "$got" = "$2" ] && [ "$app" = "$BUNDLE" ]; then echo "PASS  $1 -> $got"
  else echo "FAIL  $1 -> expected $2, got '${got:-none}' (front app: ${app:-?})"; fail=1; fi
}
jump() { "$BIN" --demo-server "$NAME" --jump-session "$1" >/dev/null; sleep 0.7; }

tt kill-server 2>/dev/null
for s in s1 s2 s3 s4 s5; do tt new-session -d -s "$s" -x 100 -y 30; done

echo "== $APP: 3 windows, one session each =="
for s in s1 s2 s3; do TTYS+=("$(open_window "$s")"); sleep 1; done
sleep 1
jump s1; check "jump to s1 (window behind)" s1
jump s2; check "jump to s2 (window behind)" s2
jump s3; check "jump to s3" s3
jump s1; check "jump to s1 again" s1

if [ "$KIND" = iterm ]; then
  echo "== $APP: 1 window, 2 tabs (s4 first, s5 in a second tab) =="
  TTYS+=("$(open_window s4)"); sleep 1
  TTYS+=("$(open_tab s5)"); sleep 1
  jump s4; check "jump to s4 (tab behind)" s4
  jump s5; check "jump to s5 (tab behind)" s5
  jump s4; check "jump to s4 again" s4
fi
exit $fail
