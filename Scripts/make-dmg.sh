#!/bin/bash
#
# Fabrique build/Cocker.dmg à partir de build/Cocker.app.
#
# Une image disque plutôt qu'une archive : l'utilisateur double-clique, fait
# glisser l'app sur Applications, et c'est fini. Un zip l'oblige à dézipper
# puis à déplacer lui-même — deux gestes de plus, et une app qui finit souvent
# dans Téléchargements.
#
#   ./Scripts/make-dmg.sh [version]
#
# Sans argument, la version est lue dans l'Info.plist du bundle.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Cocker.app"
STAGING="$ROOT/build/dmg-staging"

cd "$ROOT"

if [[ ! -d "$APP" ]]; then
	echo "✗ $APP est absent — lance d'abord ./Scripts/bundle.sh" >&2
	exit 1
fi

VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
	"$APP/Contents/Info.plist")}"
DMG="$ROOT/build/Cocker-$VERSION.dmg"

if ! command -v create-dmg >/dev/null; then
	echo "✗ create-dmg est absent : brew install create-dmg" >&2
	exit 1
fi

echo "→ Fond de l'image disque"
swift "$ROOT/Scripts/make-dmg-background.swift"

# create-dmg copie tout ce qu'il trouve dans le dossier source : il ne doit
# contenir que l'app, sinon les fichiers parasites atterrissent dans la fenêtre.
echo "→ Préparation"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"

echo "→ Assemblage"
# Les positions correspondent à celles dessinées dans le fond : les changer ici
# sans changer le script du fond décale la traînée de pattes.
create-dmg \
	--volname "Cocker $VERSION" \
	--background "$ROOT/build/dmg-background.tiff" \
	--window-pos 200 120 \
	--window-size 640 400 \
	--icon-size 128 \
	--icon "Cocker.app" 170 190 \
	--app-drop-link 470 190 \
	--hide-extension "Cocker.app" \
	--no-internet-enable \
	"$DMG" \
	"$STAGING" >/dev/null

rm -rf "$STAGING"

# L'image disque se signe elle aussi : sans quoi Gatekeeper refuse le conteneur
# alors même que l'app qu'il porte est notarisée.
IDENTITY="${COCKER_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && "${COCKER_ADHOC:-0}" != "1" ]]; then
	IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' '/Developer ID Application/ { print $2; exit }')
fi

if [[ -n "$IDENTITY" ]]; then
	echo "→ Signature de l'image"
	codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

echo "✓ $DMG"
