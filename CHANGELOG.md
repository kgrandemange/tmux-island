# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.1.1] - 2026-11-21

### Fixed
- The "+N" counter of the compact island was cut by the edge of the island with 7 or more agents. It now always fits
  (up to six dots, then four dots and the counter).
- With many sessions, the bottom of the expanded island (the sessions and the shortcuts) was pushed out of its window.
  The list of sessions now scrolls after five rows.

### Added
- An "All agents" row in the expanded island when the compact island cannot show every agent: one dot per agent,
  with the agent's name on hover and a click to jump to it.

## [1.1.0] - 2026-11-21

### Added
- **English interface**: every text now exists in English and French and follows the system language (English is the
  fallback). Adding a language only needs a new `Localization/<code>.lproj` folder (see CONTRIBUTING.md).
- Keyboard first: agents are selected with `1`-`9` by physical key, so layouts that need Shift for digits (French
  AZERTY) work without it, keypad included.
- Demo GIFs, a "Keyboard first" section and the blue "in the background" state in the README and the website.

### Changed
- The macOS permission prompt for controlling iTerm2 / Terminal is localized too.
- Website and README screenshots are shown in the visitor's language.

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
