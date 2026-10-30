#!/usr/bin/env bash
# Crea dist/SiteLink-Setup.exe (installatore + app in un solo file) anche da Mac/Linux (serve l'SDK .NET 8).
set -euo pipefail
cd "$(dirname "$0")"
rm -rf dist; mkdir dist
dotnet publish src/SiteLink.csproj -c Release -r win-x64 --self-contained \
  -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o dist/_pub
mv dist/_pub/SiteLink.exe dist/SiteLink-Setup.exe
rm -rf dist/_pub
ls -lh dist/SiteLink-Setup.exe
