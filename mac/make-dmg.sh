#!/usr/bin/env bash
# Crea dist/SiteLink.dmg: finestra con sfondo, SiteLink.app e scorciatoia ad Applications.
# Il layout è impostato dal Finder stesso (AppleScript) su un volume montato, così il
# .DS_Store è quello "nativo" e funziona anche sulle altre versioni di macOS.
# Nessun token dentro. Richiede Xcode (swift). Durante l'esecuzione si aprirà brevemente una finestra del Finder.
set -euo pipefail
cd "$(dirname "$0")"
VOL="SiteLink"; MNT="/Volumes/$VOL"
[ ! -d "$MNT" ] || { echo "Espelli prima il volume $MNT"; exit 1; }

rm -rf dist; mkdir -p dist/stage dist/bg
OUT=dist/stage ./build.sh
swift tools/make_dmg_background.swift dist/bg
tiffutil -cathidpicheck dist/bg/background.png dist/bg/background@2x.png -out dist/bg/background.tiff

RW=dist/rw.dmg
hdiutil create -size 40m -fs HFS+ -volname "$VOL" -ov "$RW" >/dev/null
hdiutil attach "$RW" -noautoopen -nobrowse -mountpoint "$MNT" >/dev/null
trap 'hdiutil detach "$MNT" -force >/dev/null 2>&1 || true' EXIT

cp -R dist/stage/SiteLink.app "$MNT/"
ln -s /Applications "$MNT/Applications"
mkdir "$MNT/.background"; cp dist/bg/background.tiff "$MNT/.background/background.tiff"
hdiutil detach "$MNT" >/dev/null
hdiutil attach "$RW" -noautoopen -mountpoint "$MNT" >/dev/null   # senza -nobrowse: il Finder deve vederlo

osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "SiteLink.app" of container window to {170, 200}
    set position of item "Applications" of container window to {490, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
cp AppIcon.icns "$MNT/.VolumeIcon.icns"; SetFile -a C "$MNT"   # icona del volume (dopo il Finder)
sync; sleep 2
hdiutil detach "$MNT" >/dev/null
trap - EXIT
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o dist/SiteLink.dmg >/dev/null
swift tools/set_file_icon.swift AppIcon.icns dist/SiteLink.dmg
rm -rf dist/stage dist/bg "$RW"
ls -lh dist/SiteLink.dmg
