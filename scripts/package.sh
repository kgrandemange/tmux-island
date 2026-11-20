#!/usr/bin/env bash
# Construit l'archive de diffusion : build/release/TmuxIsland.zip (+ empreinte SHA-256).
#  - Apple Silicon (arm64) uniquement, macOS 14+.
#  - Symboles retirés (`strip`) : les noms de fonctions ne sont plus lisibles dans le binaire.
#  - Signature « ad hoc » (pas de compte développeur Apple, donc pas de notarisation) :
#    au premier lancement, macOS demande une confirmation (voir README).
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh
version="$(cat VERSION)"
out="build/release"
rm -rf "$out"; mkdir -p "$out"
cp -R build/TmuxIsland.app "$out/TmuxIsland.app"
strip -x "$out/TmuxIsland.app/Contents/MacOS/TmuxIsland"
codesign --force --deep --sign - "$out/TmuxIsland.app" >/dev/null
codesign --verify --deep --strict "$out/TmuxIsland.app"
# Ne plus jamais publier un binaire qui contiendrait un chemin personnel.
if strings -a "$out/TmuxIsland.app/Contents/MacOS/TmuxIsland" | grep -qE "/Users/($USER|kevin)"; then
  echo "✗ le binaire contient un chemin personnel : abandon"; exit 1
fi
(cd "$out" && ditto -c -k --keepParent TmuxIsland.app TmuxIsland.zip && shasum -a 256 TmuxIsland.zip > TmuxIsland.zip.sha256)
echo "✓ $out/TmuxIsland.zip  (version $version, $(du -h "$out/TmuxIsland.zip" | cut -f1))"
cat "$out/TmuxIsland.zip.sha256"
