#!/usr/bin/env bash
# Crea l'APK firmato: dist/SiteLink-Android.apk (anche da riga di comando, senza aprire Android Studio).
#   ./build-apk.sh            -> firma con keystore.properties se esiste, altrimenti con la chiave di debug
# Richiede: un JDK 17 (vedi README) e l'SDK Android in ~/Library/Android/sdk (vedi README).
set -euo pipefail
cd "$(dirname "$0")"
# Serve un JDK 17 o 21 (il JDK 25 di Android Studio è troppo nuovo per Gradle 8).
JDK17=$(ls -d "$HOME"/Library/Android/jdk/jdk-17*/Contents/Home 2>/dev/null | head -1)
export JAVA_HOME="${JAVA_HOME:-$JDK17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
[ -x "$JAVA_HOME/bin/java" ] || { echo "JDK 17 non trovato (vedi README): imposta JAVA_HOME"; exit 1; }
[ -d "$ANDROID_HOME" ] || { echo "SDK Android non trovato in $ANDROID_HOME"; exit 1; }

if [ -f keystore.properties ]; then TASK=assembleRelease; SRC=app/build/outputs/apk/release/app-release.apk
else echo "keystore.properties assente: APK firmato con la chiave di debug (solo per prove)"; TASK=assembleDebug; SRC=app/build/outputs/apk/debug/app-debug.apk; fi

./gradlew "$TASK" --console=plain
mkdir -p dist && cp "$SRC" dist/SiteLink-Android.apk
ls -lh dist/SiteLink-Android.apk
APKSIGNER=$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
"$APKSIGNER" verify --print-certs dist/SiteLink-Android.apk 2>&1 | grep -v WARNING | head -3
