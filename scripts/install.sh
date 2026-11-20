#!/usr/bin/env bash
# Construit l'app, l'installe dans ~/Applications (emplacement stable pour l'élément de connexion) et la lance.
# Option : --login pour l'activer aussi au démarrage de la session.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh
dest="$HOME/Applications/TmuxIsland.app"
mkdir -p "$HOME/Applications"
pkill -x TmuxIsland 2>/dev/null || true
sleep 1
rm -rf "$dest"
cp -R build/TmuxIsland.app "$dest"
if [ "${1:-}" = "--login" ]; then "$dest/Contents/MacOS/TmuxIsland" --enable-login; fi
open "$dest"
echo "✓ installé dans $dest"
echo "  Lancement à la connexion : menu de la barre de menus › « Lancer à la connexion » (ou ./scripts/install.sh --login)"
