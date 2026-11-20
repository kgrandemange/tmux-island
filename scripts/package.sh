#!/usr/bin/env bash
# Construit l'app et l'archive en build/TmuxIsland-<version>.zip (prête à être distribuée), avec son empreinte SHA-256.
# L'app est signée « ad hoc » (pas de compte développeur) : au premier lancement, clic droit › Ouvrir.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh
version="$(cat VERSION)"
zip="build/TmuxIsland-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent build/TmuxIsland.app "$zip"
echo "✓ $zip"
shasum -a 256 "$zip"
