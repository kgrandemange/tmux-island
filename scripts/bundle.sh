#!/usr/bin/env bash
# Builds build/TmuxIsland.app (menu bar agent, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
version="$(cat VERSION 2>/dev/null || echo 0.0.0)"
app="build/TmuxIsland.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/TmuxIsland "$app/Contents/MacOS/TmuxIsland"
# Translations (Localization/<language>.lproj): macOS picks the one matching the system language.
cp -R Localization/*.lproj "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>fr</string></array>
  <key>CFBundleName</key><string>TmuxIsland</string>
  <key>CFBundleIdentifier</key><string>io.github.kgrandemange.tmux-island</string>
  <key>CFBundleExecutable</key><string>TmuxIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>To select the right tab in iTerm2 / Terminal.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1 || true
echo "✓ $app"
