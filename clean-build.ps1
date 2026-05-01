#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

Remove-Item -Path ".\windows\prebuilt" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path ".\example\build" -Recurse -Force -ErrorAction SilentlyContinue
flutter clean
.\scripts\build_all.ps1 2>&1 | Tee-Object -FilePath output.log
Set-Location .\example
flutter clean
flutter run -d windows --release 2>&1 | Tee-Object -FilePath output.log