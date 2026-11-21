# Security policy

## Reporting a vulnerability

Please report security issues **privately** through GitHub:
[Report a vulnerability](https://github.com/kgrandemange/tmux-island/security/advisories/new).
Do not open a public issue for something that could be exploited.

You can expect an acknowledgement within a few days. This is a small side project maintained by one person, so please be
patient, and thank you for helping keep users safe.

## Scope and design notes

- TmuxIsland runs locally with your user's privileges and is **not sandboxed**: it needs to run `tmux`, read process
  information, and (optionally) send keystrokes to your panes.
- **It contains no networking code.** It reads tmux, the tail of Claude Code transcripts, `~/.claude/sessions` and its own
  state files in `~/.local/state/tmux-island`.
- It changes your configuration only when you run an install script yourself (`scripts/install-claude-hooks.sh`, which
  backs up `~/.claude/settings.json` first).
- The app is ad-hoc signed and **not notarized** (notarization requires a paid Apple developer account). Verify
  downloads with the published SHA-256; releases are built by GitHub Actions from the tagged commit.

## Supported versions

Only the latest release receives fixes.
