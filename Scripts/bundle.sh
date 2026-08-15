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

# Les traductions vont directement dans le bundle plutôt que d'être déclarées
# comme ressources SwiftPM : `Text("…")` cherche dans Bundle.main, pas dans
# Bundle.module, et c'est Bundle.main qui compte une fois l'app assemblée.
for lproj in "$ROOT"/Resources/*.lproj; do
	[[ -d "$lproj" ]] || continue
	cp -R "$lproj" "$APP/Contents/Resources/"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signature.
#
# Avec un Developer ID dans le trousseau, on signe pour de bon : c'est ce que
# la notarisation exige, et le « hardened runtime » en fait partie. Sans lui —
# le cas de tout contributeur sans compte Apple — on retombe sur une signature
# ad hoc, suffisante pour lancer l'app localement.
#
# Sans aucune signature, SMAppService refuse d'inscrire l'app au démarrage et
# macOS redemande l'autorisation à chaque recompilation.
IDENTITY="${COCKER_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && "${COCKER_ADHOC:-0}" != "1" ]]; then
	IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' '/Developer ID Application/ { print $2; exit }')
fi

if [[ -n "$IDENTITY" ]]; then
	echo "→ Signature Developer ID"
	# --options runtime : le hardened runtime, sans lequel Apple refuse de
	#   notariser. Cocker n'a besoin d'aucune dérogation : il restreint ce
	#   qu'on charge dans notre processus, pas les programmes qu'on lance.
	# --timestamp : horodatage signé par Apple, exigé lui aussi. Il demande
	#   un accès réseau ; COCKER_ADHOC=1 permet de s'en passer hors ligne.
	codesign --force --options runtime --timestamp \
		--sign "$IDENTITY" "$APP"
else
	echo "→ Signature ad hoc (aucun Developer ID trouvé)"
	codesign --force --sign - --identifier pro.menut.cocker "$APP" >/dev/null
fi

echo "✓ $APP"
