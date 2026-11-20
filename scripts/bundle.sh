#!/usr/bin/env bash
# Construit build/TmuxIsland.app (agent menu bar, sans icône Dock).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
version="$(cat VERSION 2>/dev/null || echo 0.0.0)"
app="build/TmuxIsland.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
cp .build/release/TmuxIsland "$app/Contents/MacOS/TmuxIsland"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>TmuxIsland</string>
  <key>CFBundleIdentifier</key><string>dev.kevin.tmux-island</string>
  <key>CFBundleExecutable</key><string>TmuxIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Pour sélectionner le bon onglet dans iTerm2 / Terminal.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1 || true
echo "✓ $app"
