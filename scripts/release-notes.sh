#!/usr/bin/env bash
# Prints the release notes for a version: its CHANGELOG.md section plus the install instructions.
# Usage: scripts/release-notes.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: release-notes.sh <version>}"
awk -v v="$version" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/ { exit }
  found { print }
' CHANGELOG.md
cat <<NOTES

---

**Install** (macOS 14+, Apple Silicon)

\`\`\`
brew tap kgrandemange/tap
brew trust --tap kgrandemange/tap   # Homebrew asks you to trust third-party taps (once)
brew install --cask tmuxisland      # or: brew upgrade --cask tmuxisland
\`\`\`

Or download \`TmuxIsland.zip\` below, unzip it and drag \`TmuxIsland.app\` to Applications.
The app is not notarized (Apple's notarization needs a paid developer account): on first launch, right-click › Open.

**Verify the download** with \`shasum -a 256 TmuxIsland.zip\` (checksum in \`TmuxIsland.zip.sha256\`).
This archive was built by GitHub Actions from the tagged commit (see the *Release* workflow run).
NOTES
