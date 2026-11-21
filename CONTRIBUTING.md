# Contributing to TmuxIsland

Thanks for your interest! TmuxIsland is a small macOS app (Swift, SwiftUI + AppKit, no third-party dependency).
Bug reports, ideas and pull requests are welcome.

## Build and run

Requirements: macOS 14+ on Apple Silicon, the Xcode command line tools (`xcode-select --install`), tmux 3.x.

```bash
swift build -c release           # build
swift test                       # run the tests (some use a private tmux server and are skipped if tmux is missing)
./scripts/install.sh             # build, install into ~/Applications and launch
```

## Try it safely with fictional data

`scripts/demo/demo.sh` starts an isolated tmux server with fictional projects and scripted fake agents, and launches the
app in `--demo-server` mode (only that server is shown, history is kept in memory, your real files are untouched).
See `scripts/demo/SHOOTING.md`. Handy for screenshots and for testing without real agents.

Other debug flags: `TmuxIsland --snapshot out.png` renders the island with your sessions, `--demo-images dir` renders the
documentation images, `--animtest dir` records frames of a real open/close.

## Project layout

| Path | What it is |
|---|---|
| `Sources/TmuxIsland/` | the app |
| `Tests/TmuxIslandTests/` | unit and integration tests |
| `scripts/` | install, packaging, Claude Code hooks, demo environment |
| `docs/` | the website (GitHub Pages) and its assets |

Entry points: `StateResolver.swift` (the agent state machine, a pure function with tests), `AgentStore.swift` (polling and
alerts), `IslandController.swift` / `IslandView.swift` (the window and the interface), `FocusService.swift` (jumping to a
pane).

## Pull requests

- Keep them focused; explain what and why. Small is better.
- Add or update tests when you change behavior (the state machine and the screen parsers are easy to cover).
- Run `swift test` before pushing; CI runs it on Apple Silicon.
- Do not include personal data in a diff (paths, names, project names, tokens), including in screenshots.
- **Translations**: the interface strings live in `Localization/<language>.lproj/Localizable.strings` (English and French
  today), plus `InfoPlist.strings` for the macOS permission prompt. To add a language, copy `Localization/en.lproj` to
  `Localization/<code>.lproj`, translate the values (keep the keys and the `%@` / `%d` placeholders), and add the code to
  `CFBundleLocalizations` in `scripts/bundle.sh`. `swift test` checks that every language has the same keys and placeholders.
  Force a language when trying it: `TMUXISLAND_LANG=fr`.
- Never hard-code user-facing text: use `L10n.tr("key")` (or `L10n.plural`) and add the key to every language.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## About AI-assisted code

This project was built with [Claude Code](https://claude.com/claude-code), directed and reviewed by the maintainer.
AI-assisted contributions are welcome under the same bar as any other: you understand it, you tested it, you can
answer review questions about it.

## Releases

Maintainers publish a release by bumping `VERSION`, updating `CHANGELOG.md`, and pushing a `vX.Y.Z` tag: the *Release*
workflow builds the app from that commit and publishes `TmuxIsland.zip` with its SHA-256. The Homebrew cask in
`kgrandemange/homebrew-tap` is then updated with the new version and checksum.
