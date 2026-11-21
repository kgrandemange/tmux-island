# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-21

First stable release, and the source code is now open under the MIT license.

### Added
- Open source (MIT), contribution guide, security policy, issue templates, continuous integration, and releases built by
  GitHub Actions from the tagged commit.
- A calm **"in the background"** state (blue ring) for agents whose turn is over but whose background shells or
  sub-agents are still running, with no false "done" alert.
- A smoother open/close animation: the island morphs open with a soft bounce, and closes faster and calmer.
- A demo environment (`scripts/demo`) and a presentation video built from fictional data.

### Security
- Security review before opening the code. Hardened: out-of-range process ids and malformed Claude session files can no
  longer crash the app; session ids are validated before building transcript paths; tty names are validated and escaped
  before reaching AppleScript; the `--demo-server` name cannot escape tmux's socket directory; only sockets owned by
  you are used; the state directory is private (0700); the hook script validates every input it writes; the hook
  installer quotes paths and keeps the permissions of `settings.json`; the website has a content security policy.

### Changed
- Code comments are in English, large files were split and dead code removed (no behavior change).
- The Homebrew cask now downloads from this repository's releases; the website is served from `docs/` of this repository.


## [0.1.2] - 2026-11-21
- Smoother open/close animation.

## [0.1.1] - 2026-11-20
- Agents with background shells are shown as "in the background".

## [0.1.0] - 2026-11-20
- First public build: island around the notch, agent states from Claude Code's session status, hooks and screen
  detection, one-click jump to the right tmux pane, permission choices, pane preview, history, focus mode, multi-display,
  configurable global shortcuts, several tmux servers.
