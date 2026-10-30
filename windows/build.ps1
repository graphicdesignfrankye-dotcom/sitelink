# Crea dist\SiteLink-Setup.exe (installatore + app in un solo file). Da PowerShell, nella cartella windows\
# Richiede l'SDK .NET 8 (https://dotnet.microsoft.com/download).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
Remove-Item dist -Recurse -Force -ErrorAction SilentlyContinue
dotnet publish src\SiteLink.csproj -c Release -r win-x64 --self-contained `
  -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o dist\_pub
Move-Item dist\_pub\SiteLink.exe dist\SiteLink-Setup.exe
Remove-Item dist\_pub -Recurse -Force
Get-Item dist\SiteLink-Setup.exe | Select-Object Name, Length
