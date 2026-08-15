#!/bin/bash
#
# Assemble Cocker.app à partir de l'exécutable produit par SwiftPM.
#
# SwiftPM ne sait produire qu'un binaire ; macOS exige un bundle pour un
# LSUIElement, pour SMAppService et pour que SwiftUI trouve son Info.plist.
#
#   ./Scripts/bundle.sh [debug|release]   (release par défaut)

set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Cocker.app"

cd "$ROOT"

echo "→ Compilation ($CONFIGURATION)"
swift build -c "$CONFIGURATION"

BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/Cocker"
if [[ ! -x "$BINARY" ]]; then
	echo "✗ Binaire introuvable : $BINARY" >&2
	exit 1
fi

ICON="$ROOT/Resources/Cocker.icns"
if [[ ! -f "$ICON" || "$ROOT/Scripts/make-icon.swift" -nt "$ICON" ]]; then
	echo "→ Génération de l'icône"
	swift "$ROOT/Scripts/make-icon.swift"
fi

echo "→ Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Cocker"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/Cocker.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signature ad hoc : sans elle, SMAppService refuse d'inscrire l'app au
# démarrage et macOS redemande l'autorisation à chaque recompilation.
echo "→ Signature ad hoc"
codesign --force --sign - --identifier pro.menut.cocker "$APP" >/dev/null

echo "✓ $APP"
