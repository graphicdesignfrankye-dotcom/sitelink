#!/usr/bin/env bash
# Compila (universale Apple Silicon + Intel) e impacchetta SiteLink.app
# Variabile opzionale: OUT=cartella (default build)
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
APP="${OUT:-build}/SiteLink.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/SiteLink" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Creato $APP"
