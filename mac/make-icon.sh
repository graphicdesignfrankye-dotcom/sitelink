#!/usr/bin/env bash
# Rigenera AppIcon.icns dallo script di disegno.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build/AppIcon.iconset; mkdir -p build
swift tools/make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
echo "Creato AppIcon.icns"
